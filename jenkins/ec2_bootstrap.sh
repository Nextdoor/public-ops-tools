#/bin/bash
#
# = About
#
# This script contains all of the steps we need to launch a completely
# stock EC2 host and convert it into a Jenkins slave. This includes installing
# an arbirtary set of packages, custom aptitude repos, ruby, java, etc.
#
# == Usage
#
# Below is a script you could use inside the Jenkins EC2 Instance launcher
# plugin to configure a host. Take note of the `\n` at the end of ecah newline
# in the variables below, these are critical.
#
#   #!/bin/bash
#   export HTTPS_REPOS=$"
#   deb https://s3.amazonaws.com/my.repo.com/repos/precise stable main\n
#   deb https://s3.amazonaws.com/my.repo.com/repos/precise unstable main\n"
#
#   export S3_REPOS=$"
#   deb s3://ACCESS_KEY:[SECRET_ID]@s3.amazonaws.com/my.repo.com/debian_repos/precise/ stable/\n
#   deb s3://ACCESS_KEY:[SECRET_iD]@s3.amazonaws.com/my.repo.com/debian_repos/lucid/ stable/\n"
#
#   GITHUB="https://raw.githubusercontent.com/Nextdoor/public-ops-tools/master/"
#   BOOTSCRIPT="${GITHUB}/jenkins/ec2_bootstrap.sh"
#   curl -q --insecure $BOOTSCRIPT | sudo -E /bin/bash
#
# == Authors
#
# Matt Wise <matt@nextdoor.com>
#

# Ensure that on any failure, we exit, but also make sure that the contents
# of this script are not outputted to the console. This script writes out
# some credentials (that it gets from an environment variable) and we do
# not want this outputted to logs.
set +x
set -e

# Sleep for 15 seconds.. seems that there may be some background things going on
# when the node first boots up that prevents the apt-installs below to work. Waiting
# seems seems to help.
sleep 15

# Default list of packages that are installed via APT. These are required to
# start up Jenkins, and are base packages required for other types of
# development (like compiling code). Space-separated list.
DEFAULT_PACKAGES=" \
  default-jre-headless \
  cowbuilder \
  git \
  libcommons-codec-java \
  daemon \
  expect \
  gawk \
  ia32-libs lib32stdc++6 \
  libyaml-dev \
  libsqlite3-dev \
  sqlite3 \
  autoconf \
  libgdbm-dev \
  libncurses5-dev \
  automake \
  libtool \
  bison \
  libffi-dev \
  libmemcached-dev \
  python3 \
  nodejs \
  npm"

# Ruby and all the Ruby dependencies (RVM is manually installed later
# automatically by the RVM Jenkins Plugin)
# (http://stackoverflow.com/questions/9056008/installed-ruby-1-9-3-
#  with-rvm-but-command-line-doesnt-show-ruby-v/9056395#9056395)
#
RUBY_PACKAGES="ruby rubygems libgdbm-dev bison libffi-dev zlib1g-dev
               libssl-dev pkg-config"

# Match the "Remote FS root" setting from the Jenkins EC2 Plugin
JENKINS_HOME="/mnt/jenkins"

# Used to discover what ephemeral storage volumes were setup for this host.
METADATA_URL_BASE="http://169.254.169.254/2012-01-12"

# Set up a couple of misc system settings...
initial_system_setup() {
  # Don't use the EC2 Apt mirrors since they go down more regularly than Ubuntu's
  sed -i -e  's/us-east-1\.ec2\.//g' /etc/apt/sources.list

  # Ensure that we can do git clones without strict host key checking
  cat <<EOF >> ~ubuntu/.ssh/config
Host *
        StrictHostKeyChecking no
EOF

  # Do an Apt-Get update so that later package installs can succeed
  DEBIAN_FRONTEND=noninteractive apt-get -y -q update
}

raid_ephemeral_storage() {
  # Ensure mdadm is installed
  DEBIAN_FRONTEND=noninteractive apt-get -y --force-yes -q install mdadm

  # Configure Raid - take into account xvdb or sdb
  root_drive=`df -h | grep -v grep | awk 'NR==2{print $1}'`

  if [ "$root_drive" == "/dev/xvda1" ]; then
    echo "Detected 'xvd' drive naming scheme (root: $root_drive)"
    DRIVE_SCHEME='xvd'
  else
    echo "Detected 'sd' drive naming scheme (root: $root_drive)"
    DRIVE_SCHEME='sd'
  fi

  # figure out how many ephemerals we have by querying the metadata API, and then:
  #  - convert the drive name returned from the API to the hosts DRIVE_SCHEME, if necessary
  #  - verify a matching device is available in /dev/
  drives=""
  ephemeral_count=0
  ephemerals=$(curl --silent $METADATA_URL_BASE/meta-data/block-device-mapping/ | grep ephemeral)
  for e in $ephemerals; do
    echo "Probing $e .."
    device_name=$(curl --silent $METADATA_URL_BASE/meta-data/block-device-mapping/$e)
    # might have to convert 'sdb' -> 'xvdb'
    device_name=$(echo $device_name | sed "s/sd/$DRIVE_SCHEME/")
    device_path="/dev/$device_name"

    # test that the device actually exists since you can request more ephemeral drives than are available
    # for an instance type and the meta-data API will happily tell you it exists when it really does not.
    if [ -b $device_path ]; then
      echo "Detected ephemeral disk: $device_path"
      drives="$drives $device_path"
      ephemeral_count=$((ephemeral_count + 1 ))
    else
      echo "Ephemeral disk $e, $device_path is not present. skipping"
    fi
  done

  if [ "$ephemeral_count" = 0 ]; then
    echo "No ephemeral disk detected. exiting"
    exit 0
  fi

  # ephemeral0 is typically mounted for us already. umount it here
  umount /mnt

  # overwrite first few blocks in case there is a filesystem, otherwise mdadm will prompt for input
  for drive in $drives; do
    dd if=/dev/zero of=$drive bs=4096 count=1024
  done

  partprobe
  mdadm --create --verbose /dev/md0 --level=0 -c256 --raid-devices=$ephemeral_count $drives
  echo DEVICE $drives | tee /etc/mdadm.conf
  mdadm --detail --scan | tee -a /etc/mdadm.conf
  blockdev --setra 65536 /dev/md0
  mkfs -t ext3 /dev/md0
  mount -t ext3 -o noatime /dev/md0 /mnt

  # Remove xvdb/sdb from fstab
  chmod 777 /etc/fstab
  sed -i "/${DRIVE_SCHEME}b/d" /etc/fstab
}
prep_for_jenkins() {
  # Set up a location for Jenkins on the faster instance-storage
  mkdir $JENKINS_HOME && chown ubuntu:ubuntu $JENKINS_HOME
}


create_apt_sources() {
  # Install the Nextdoor public repos and install the apt-transport-s3 package
  echo -e "${HTTPS_REPOS}" > /etc/apt/sources.list.d/https.sources.list

  # Explicitly install the apt-transport-s3 package from our public repo first
  DEBIAN_FRONTEND=noninteractive apt-get -y -q update
  DEBIAN_FRONTEND=noninteractive apt-get -y --force-yes -q install apt-transport-s3

  # Now, install the apt-transport-s3 backed repos
  echo -e "${S3_REPOS}" > /etc/apt/sources.list.d/s3.sources.list
  DEBIAN_FRONTEND=noninteractive apt-get -y -q update
}

install_packages() {
  # Install all of the required default packages via aptitude
  DEBIAN_FRONTEND=noninteractive apt-get -y --force-yes -q install $DEFAULT_PACKAGES
}

install_ruby() {
  # Install RVM to the ubuntu user (required for the Jenkins RVM Plugin), and install Ruby
  # versions 1.8.7 and 1.9.3 immediately. If we don't, Jenkins has a bad habit of trying to do the
  # install multiple times concurrently (if you launch multiple concurrent jobs), and they conflict with
  # each other.
  DEBIAN_FRONTEND=noninteractive apt-get --purge -y --force-yes remove ruby-rvm
  DEBIAN_FRONTEND=noninteractive apt-get -y --force-yes -q install $RUBY_PACKAGES

  curl -L https://get.rvm.io | bash -s stable --ruby --autolibs=enable --auto-dotfiles
}

function main() {
  initial_system_setup
  raid_ephemeral_storage
  prep_for_jenkins
  create_apt_sources
  install_packages
  install_ruby
}

main $*
