#/bin/bash
#
# = About
#
# This script contains all of the steps we need to launch a completely
# stock EC2 host and convert it into a Jenkins slave. This includes installing
# an arbitrary set of packages, custom aptitude repos, ruby, java, etc.
#
# == Usage
#
# Below is a script you could use inside the Jenkins EC2 Instance launcher
# plugin to configure a host.
#
#   #!/bin/bash
#
#   export AWS_ACCESS_KEY_ID=<access_key>
#   export AWS_SECRET_ACCESS_KEY=<secret_id>
#
#   GITHUB="https://raw.githubusercontent.com/Nextdoor/public-ops-tools/master/"
#   BOOTSCRIPT="${GITHUB}/jenkins/ec2_bootstrap.sh"
#   curl -q --insecure $BOOTSCRIPT | sudo -E /bin/bash
#
# == Authors
#
# Matt Wise <matt@nextdoor.com>
# Chuck Karish <chuck@nextdoor.com>

# Discover what version of the OS we're running so we can set variables based on that.
source /etc/lsb-release

# Enable unattended use of apt-get.
export DEBIAN_FRONTEND=noninteractive

# Packages that are installed on every worker host. Other packages
# that are needed to fulfill a particular host type's role should
# be installed by a job that needs them, the first time it runs.
DEFAULT_PACKAGES="
  openjdk-7-jdk
  git"

# Tools for building .deb archives.
DEBIAN_BUILD_PACKAGES="
  debhelper
  quilt"

install_nextdoor_gpg_key() {
    cat << EOF | apt-key add -
-----BEGIN PGP PUBLIC KEY BLOCK-----
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
-----END PGP PUBLIC KEY BLOCK-----
EOF
}

# Set up a couple of misc system settings...
initial_system_setup() {
  # Ensure that we can do git clones without strict host key checking
  cat <<EOF >> ~ubuntu/.ssh/config
Host *
        StrictHostKeyChecking no
EOF
  chown ubuntu.ubuntu ~ubuntu/.ssh/config

  install_nextdoor_gpg_key

  # Do an Apt-Get update so that later package installs can succeed
  apt-get -y -q update
}

raid_ephemeral_storage() {
  # This must be run after every reboot.

  # If the volume is already set up as an md0 raid, skip this func
  grep -q md0 /etc/mtab && return

  # Make sure that mdadm is installed
  install_packages mdadm xfsprogs

  # Configure Raid - take into account xvdb or sdb
  root_drive=`df | awk '$NF=="/" {print $1}'`

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

  # Used to discover what ephemeral storage volumes were set up for this host.
  METADATA_URL_BASE="http://169.254.169.254/2012-01-12"
  drives=""
  ephemeral_count=0
  ephemerals=$(curl --silent $METADATA_URL_BASE/meta-data/block-device-mapping/ | grep ephemeral)
  for e in $ephemerals; do
    echo "Probing $e .."
    device_name=$(curl --silent $METADATA_URL_BASE/meta-data/block-device-mapping/$e)
    # might have to convert 'sdb' -> 'xvdb'
    device_path=$(sed "s/sd/$DRIVE_SCHEME/" <<< /dev/$device_name)

    # test that the device actually exists since you can request more ephemeral drives
    # than are available for an instance type and the meta-data API will happily tell
    # you it exists when it really does not.
    if [ -b $device_path ]; then
      echo "Detected ephemeral disk: $device_path"
      drives="$drives $device_path"
      ((ephemeral_count ++)) || true
    else
      echo "Ephemeral disk $e, $device_path is not present. skipping"
    fi
  done

  if [[ "$ephemeral_count" = 0 ]]; then
    echo "No ephemeral disk detected. exiting"
    exit 0
  fi

  # ephemeral0 is typically mounted for us already. umount it here
  umount /mnt || true

  # overwrite first few blocks in case there is a filesystem, otherwise mdadm will prompt for input
  for drive in $drives; do
    dd if=/dev/zero of=$drive bs=4096 count=1024
  done

  partprobe || true
  mdadm --create -v /dev/md0 --level=0 --chunk=256 --raid-devices=$ephemeral_count $drives ||
    true
  echo DEVICE $drives | tee /etc/mdadm.conf
  mdadm --detail --scan |
    awk '/ARRAY/{for (i=0; i<=NF; i++){if (match($i, "^UUID=")){print $1, $2, $i}}}' |
    tee -a /etc/mdadm.conf
  blockdev --setra 65536 /dev/md0

  # Format and mount
  mkfs -t xfs /dev/md0
  mount -t xfs -o noatime /dev/md0 /mnt

  # Remove xvdb/sdb from fstab
  chmod 777 /etc/fstab
  sed -i "/${DRIVE_SCHEME}b/d" /etc/fstab
}

prep_for_jenkins() {
  # Run Jenkins on the faster RAID storage
  JENKINS_HOME="/mnt/jenkins"  # Match the "Remote FS root" setting from the Jenkins EC2 Plugin
  mkdir -p $JENKINS_HOME && chown ubuntu:ubuntu $JENKINS_HOME
}

restart_raid_ephemeral_storage() {
    # docker may have files open on /mnt.
    service docker stop || true
    if [[ -f /dev/md0 ]]; then
        umount /mnt || true
        mount -t xfs -o noatime /dev/md0 /mnt
    elif grep -q md127 /proc/mdstat; then
        # This is a workaround for a bug in the RAID manager.
        # http://ubuntuforums.org/showthread.php?t=1764861
        mdadm --stop /dev/md127
        DRIVES=$(sed -n 's/DEVICE //p' /etc/mdadm.conf)
        RAID_DEVICES=$(awk '{print NF}' <<< $DRIVES)
        echo y | mdadm --create -f -v /dev/md0 -l 0 -c 256 --raid-devices=$RAID_DEVICES $DRIVES
        mount -t xfs -o noatime /dev/md0 /mnt
    else
        raid_ephemeral_storage
        prep_for_jenkins
    fi
    service docker start || true
}

create_apt_sources() {

    # Cause apt commands to Just Do It, even if we don't pass the "-y" flag.
    # This is needed to run a command (mk-build-deps) that doesn't let us pass "-y".
    if [[ ! -f /etc/apt/apt.conf.d/30apt_assume_yes.conf ]]; then
        cat > /etc/apt/apt.conf.d/30apt_assume_yes.conf << EOF
APT {
       Get {
                Assume-Yes "true";
        };
};
EOF
    fi

    if [[ ! -f '/etc/apt/sources.list.d/https.sources.list' ]]; then
        # Install the Nextdoor public repos
        cat > /etc/apt/sources.list.d/https.sources.list << EOF
deb https://s3.amazonaws.com/cloud.nextdoor.com/repos/precise stable main
deb https://s3.amazonaws.com/cloud.nextdoor.com/repos/precise unstable main
EOF
        apt-get -y -q update
    fi

    # Install the apt-transport-s3 driver if it is missing
    dpkg --status apt-transport-s3 > /dev/null || install_packages apt-transport-s3

    # Now, install the apt-transport-s3 backed repos
    if [[ ! -f '/etc/apt/sources.list.d/s3.sources.list' ]]; then
        set +x
        cat > /etc/apt/sources.list.d/s3.sources.list << EOF
deb s3://${AWS_ACCESS_KEY_ID}:[${AWS_SECRET_ACCESS_KEY}]@s3.amazonaws.com/cloud.nextdoor.com/debian_repos/precise/ stable/
deb s3://${AWS_ACCESS_KEY_ID}:[${AWS_SECRET_ACCESS_KEY}]@s3.amazonaws.com/cloud.nextdoor.com/debian_repos/precise/ unstable/
deb s3://${AWS_ACCESS_KEY_ID}:[${AWS_SECRET_ACCESS_KEY}]@s3.amazonaws.com/cloud.nextdoor.com/debian_repos/melissadata/ stable/
deb s3://${AWS_ACCESS_KEY_ID}:[${AWS_SECRET_ACCESS_KEY}]@s3.amazonaws.com/cloud.nextdoor.com/debian_repos/melissadata/ unstable/
EOF
        set -x
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
  # Install a list of Debian packages
  apt-get -y --force-yes -q install $*
}

install_ruby() {
  # Install gpg key for rvm
  su -l ubuntu -c bash -c "gpg --keyserver hkp://keys.gnupg.net --recv-keys D39DC0E3"

  # Set up Ruby, but explicitly uninstall RVM. This lets Jenkins handle the install
  # of RVM. If the package doesn't exist, we don't care if the uninstall fails.
  # (http://stackoverflow.com/questions/9056008/installed-ruby-1-9-3-
  #  with-rvm-but-command-line-doesnt-show-ruby-v/9056395#9056395)
  set +e
  apt-get --purge -y --force-yes remove ruby-rvm
  set -e

  if [[ "$DISTRIB_CODENAME" == "trusty" ]]; then
    RUBYGEM=rubygems-integration
  else
    RUBYGEM=rubygems
  fi

  # Install some ruby packages
  RUBY_PACKAGES="
      ruby
      $RUBYGEM
      bison
      libffi-dev
      libgdbm-dev
      libssl-dev
      pkg-config
      zlib1g-dev"
  install_packages $RUBY_PACKAGES

  # Su back to the Ubuntu user and install RVM under it
  su -l ubuntu -c bash -c "curl -sSL https://get.rvm.io | bash -s stable --ruby"
}

install_docker() {
  # Add the repository to your APT sources
  echo deb https://get.docker.com/ubuntu docker main > /etc/apt/sources.list.d/docker.list

  # Then import the repository key
  set +e
  apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9

  # Enable the much more tested and reliable filesystem driver AUFS
  # https://groups.google.com/forum/#!topic/docker-user/Tpi5m1I9dGU
  #
  # (Note: Our Puppet module already does this, so this is
  # just mimicking production)
  install_packages linux-image-extra-$(uname -r)

  # Install docker
  apt-get update
  install_packages lxc-docker-1.5.0

  # Ensure that Docker uses /mnt/docker for storage (so it doesn't fill up the
  # root volume). Also ensure that the docker socket file is owned by the
  # 'jenkins' group, allowing Jenkins to interact with it.
  cat << EOF >>  /etc/default/docker
TMPDIR=/mnt/tmp
DOCKER_OPTS="-g /mnt/docker -G ubuntu --storage-opt dm.basesize=20G"
EOF
  mkdir -p /mnt/tmp /mnt/docker
  set -e

  # Lastly, restart it now that we've reconfigured it.
  service docker restart
}

prepare_cowbuilder() {
    local BASE="${GITHUB}/jenkins/cowbuilder"
    local FILES="bootstrap.sh cowbuilderrc finish.sh"

    install_packages cowbuilder
    cd /tmp
    for file in $FILES; do
        curl --silent --insecure -O ${BASE}/${file}
    done
    /bin/bash ./bootstrap.sh
}

function main() {
    # Exit on any failure.
    set -e

    # Be verbose. Wherever we'd print sensitive data, we'll go silent.
    set -x

    # Sleep for 3 seconds. seems that there may be some background things going on
    # when the node first boots up that prevents the apt-installs below to work. Waiting
    # seems seems to help.
    sleep 3

    # Optional arguments: names of functions to run.
    if [[ $# -gt 0 ]]; then
        for arg in $*; do
            declare -F $arg > /dev/null || { echo "$arg: not recognized."; exit 1; }
        done

        for arg in $*; do
            echo $arg
            eval $(echo $arg)
        done
        exit
    fi

    initial_system_setup
    raid_ephemeral_storage
    prep_for_jenkins
    create_apt_sources
    install_packages $DEFAULT_PACKAGES
    install_packages $DEBIAN_BUILD_PACKAGES
    install_ruby
    install_docker
    if [[ -n "$PREPARE_COWBUILDER" ]]; then prepare_cowbuilder; fi
}

main $*
