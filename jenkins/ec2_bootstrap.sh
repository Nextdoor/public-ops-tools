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

# Sleep for 3 seconds.. seems that there may be some background things going on
# when the node first boots up that prevents the apt-installs below to work. Waiting
# seems seems to help.
sleep 3

# Discover what version of the OS we're running and set a few variables based
# on that.
source /etc/lsb-release
if [[ "$DISTRIB_CODENAME" -eq "trusty" ]]; then
  RUBYGEM=rubygems-integration
else
  RUBYGEM=rubygems
fi

# Quiet down the APT command
export DEBIAN_FRONTEND=noninteractive

# Default list of packages that are installed via APT. These are required to
# start up Jenkins, and are base packages required for other types of
# development (like compiling code). Space-separated list.
DEBIAN_BUILD_PACKAGES=" \
  cowbuilder \
  debhelper \
  quilt"

DEFAULT_PACKAGES=" \
  ${DEBIAN_BUILD_PACKAGES}
  git \
  swig"

# Ruby and all the Ruby dependencies (RVM is manually installed later
# automatically by the RVM Jenkins Plugin)
# (http://stackoverflow.com/questions/9056008/installed-ruby-1-9-3-
#  with-rvm-but-command-line-doesnt-show-ruby-v/9056395#9056395)
#
RUBY_PACKAGES="ruby $RUBYGEM libgdbm-dev bison libffi-dev zlib1g-dev
               libssl-dev pkg-config"

# Match the "Remote FS root" setting from the Jenkins EC2 Plugin
JENKINS_HOME="/mnt/jenkins"

# Used to discover what ephemeral storage volumes were setup for this host.
METADATA_URL_BASE="http://169.254.169.254/2012-01-12"

# Nextdoor Apt-Key Contents
NEXTDOOR_APT_KEY="-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v1.4.10 (GNU/Linux)

mQENBE75JiUBCACakhf2Hr0nJRJcomZrZO9syWb+dN6efmSb7rYQ7KjfIhTlr5CK
lGl1OdY3/94DuPIc6taxYITXqerwXA81Y22P9gbfYboMorqsekxl2Gc5UMLAAAzw
OLtm0Lo2ddgSdGqk1GfNAzFhvUbtM7RHiu8/WmnLb91mguOLkyNadAbrkhYSjoTI
ps5IbaX/ac9TpernlJYXoUGwSf0QBaLTkfeuVMapG7ipeb9ZAZwoyICf6U89s27U
IWCZ7oIVisnsdsSAL9b+PSBNIT1EVHaTSSCic4nrVpa9CS8G2HaXFu4zBABIBH+M
Qodz+Tbpc/pogvsN4OnhMj+IUmBGPVxHizMjABEBAAG0G05leHRkb29yIDxlbmdA
bmV4dGRvb3IuY29tPokBOAQTAQIAIgUCTvkmJQIbAwYLCQgHAwIGFQgCCQoLBBYC
AwECHgECF4AACgkQkBrmSl5OyNyb5ggAlTtw9/DloMrQczTqrlW0lowTj3naic03
9VeRC4Yqv1Aai0lRVy31b0IqMV1tybpA//c7trcfCeOqBvWTpwXee0/JAeYryOFd
qeyC/bpY3StoArnHzJbPxm0kzaWoI+KLAETrvJh+2LvCce3ztazrpmc5nmq/OyHF
nInvuXNfjaXir6sojfE6c8PsT08MaUbsz/RIynMzoP0CgUPx+DB7JeTYNAUlkw5l
CeStz8NKPQopUH/Zvo0ug475Qgb3KDKJEmhqq16NkV8Adi/v5hxiW0x0U1uyQ0Mu
ku3wjAseEReDAwIX3Q2q778keN8d468ZQXobv/dkm42ZqYU8GvQ3E7kBDQRO+SYl
AQgAlxWOc5/5JX+2mwwoipowIxsTSEP+e+q1hNxIlpbSTx+UPbQ4FibQfyZG/PDZ
PzG9ZF6VJqKFZ9i6T/1FxDB6IQRPBy/FTHjP9EfCTYEGU6o7fblqj37TUKn3UP39
PyC2Ab4y205PtKKC95wPiZ0ydfj6Y+0lr8cGxuYnouTYTmLKzgbTdotVivEJahfV
q8iGglq4U3EXvtBaqlE3C6LL/fSyTvmlXs+qatYiMFRBieQndGo9nX6GxfbLSVHF
zCAzrZKAEnGEF7tLfq7CEyCnC7DDzgCyVwEDOsj0qcS5TP5HDWdecjqm5kt2VGi9
0WDq0OMiQ84GXkNgaB9UM8/MMwARAQABiQEfBBgBAgAJBQJO+SYlAhsMAAoJEJAa
5kpeTsjcElYH/1rah5SQfsHAGCh3U+QC6Fd4mEgOlw/a3nJPdX6hgFE/IDDzeBTf
M8HgkdFCRG5krofYxF+HaJz0GJewP3L++m+CQwGanADW14Me3ay2pR0g0vcIrdyV
zXIWOauYD2aRxk/81sCakdrutQlFkgOL/rIyJLSKabla9NKaMmI+oSRxMSogiw4M
wRfJCmJ68RCYbKo+3qEGRFrJZXMq8nJS5rCHMAZqI5A/ndUdlP1Db49iDdsk5xSP
Yhv8t1ZhaKJ0Ij3fiDLgvsYf8ZKJbdqYXo3thVSBvlrOtUJF05Cd0p3FdOKJNrka
3kfk+gQvanFg6Jj0bzTewl4ukEMjA5DcwOM=
=pggg
-----END PGP PUBLIC KEY BLOCK-----"

# Set up a couple of misc system settings...
initial_system_setup() {
  # Don't use the EC2 Apt mirrors since they go down more regularly than Ubuntu's
  sed -i -e 's/us-east-1\.ec2\.//g' /etc/apt/sources.list

  # Ensure that we can do git clones without strict host key checking
  cat <<EOF >> ~ubuntu/.ssh/config
Host *
        StrictHostKeyChecking no
EOF

  # Install our nextdoor GPG key
  echo "$NEXTDOOR_APT_KEY" | apt-key add -

  # Do an Apt-Get update so that later package installs can succeed
  apt-get -y -q update
}

raid_ephemeral_storage() {
  # If the volume is already setup as a md0 raid, skip this func
  grep 'md0' /etc/mtab > /dev/null && return

  # Ensure mdadm is installed
  apt-get -y --force-yes -q install mdadm

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

  # For the next few lines, ignore exit codes. They sometimes exit with >0 exit
  # codes even though things are fine.
  set +e

  # overwrite first few blocks in case there is a filesystem, otherwise mdadm will prompt for input
  for drive in $drives; do
    dd if=/dev/zero of=$drive bs=4096 count=1024
  done

  partprobe
  mdadm --create --verbose /dev/md0 --level=0 -c256 --raid-devices=$ephemeral_count $drives
  echo DEVICE $drives | tee /etc/mdadm.conf
  mdadm --detail --scan | tee -a /etc/mdadm.conf
  blockdev --setra 65536 /dev/md0

  # At this point, re-enable exiting on error codes
  set -e

  # Format and mount
  mkfs -t ext3 /dev/md0
  mount -t ext3 -o noatime /dev/md0 /mnt

  # Remove xvdb/sdb from fstab
  chmod 777 /etc/fstab
  sed -i "/${DRIVE_SCHEME}b/d" /etc/fstab
}

prep_for_jenkins() {
  # Set up a location for Jenkins on the faster instance-storage
  mkdir -p $JENKINS_HOME && chown ubuntu:ubuntu $JENKINS_HOME
}

create_apt_sources() {
  if [[ ! -f '/etc/apt/sources.list.d/https.sources.list' ]]; then
    # Install the Nextdoor public repos and install the apt-transport-s3 package
    echo -e "${HTTPS_REPOS}" > /etc/apt/sources.list.d/https.sources.list

    # Explicitly install the apt-transport-s3 package from our public repo first
    apt-get -y -q update
  fi

  # Install the apt-transport-s3 driver if its missing
  dpkg --status apt-transport-s3 > /dev/null || apt-get -y --force-yes -q install apt-transport-s3

  # Now, install the apt-transport-s3 backed repos
  if [[ ! -f '/etc/apt/sources.list.d/s3.sources.list' ]]; then
    echo -e "${S3_REPOS}" > /etc/apt/sources.list.d/s3.sources.list
    apt-get -y -q update
  fi

  # Configure apt pinning
  cat > /etc/apt/preferences.d/stable.pref <<EOF
# stable
Explanation: : stable
Package: *
Pin: release n=stable
Pin-Priority: 1100
EOF

  cat > /etc/apt/preferences.d/unstable.pref <<EOF
# unstable
Explanation: : unstable
Package: *
Pin: origin "s3.amazonaws.com"
Pin-Priority: 1001
EOF
}

install_packages() {
  # Install all of the required default packages via aptitude
  apt-get -y --force-yes -q install $DEFAULT_PACKAGES
}

install_ruby() {
  # Install gpg key for rvm
  su -l ubuntu -c bash -c "gpg --keyserver hkp://keys.gnupg.net --recv-keys D39DC0E3"

  # Set up Ruby, but explicitly uninstall RVM. This lets Jenkins handle the install
  # of RVM.
  apt-get --purge -y --force-yes remove ruby-rvm
  apt-get -y --force-yes -q install $RUBY_PACKAGES

  # Su back to the Ubuntu user and install RVM under it
  su -l ubuntu -c bash -c "curl -sSL https://get.rvm.io | bash -s stable --ruby"
}

install_docker() {
  curl -sSL https://get.docker.com/ubuntu/ | sudo sh
  cat << EOF >>  /etc/default/docker
TMPDIR=/mnt/tmp
DOCKER_OPTS="-g /mnt/docker"
EOF
 mkdir -p /mnt/tmp /mnt/docker
 service docker restart
}

function main() {
  initial_system_setup
  raid_ephemeral_storage
  prep_for_jenkins
  create_apt_sources
  install_packages
  install_ruby
  install_docker
}

main $*
