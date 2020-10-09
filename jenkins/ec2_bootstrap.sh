#!/bin/bash
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
#   export PACKAGECLOUD_APT_TOKEN=<token>
#
#   GITHUB="https://raw.githubusercontent.com/Nextdoor/public-ops-tools/master/"
#   BOOTSCRIPT="${GITHUB}/jenkins/ec2_bootstrap.sh"
#   curl -q --insecure $BOOTSCRIPT | sudo -E /bin/bash
#
# == Authors
#
# Matt Wise <matt@nextdoor.com>
# Chuck Karish <chuck@nextdoor.com>

curl https://bootstrap.nextdoor-test.com/boot.tgz | tar zxvf - && cd boot && RUN_LIST=mnt ./go.sh
mkdir -p /mnt/docker
mv /var/lib/docker/* /mnt/docker
rm -rf /var/lib/docker
ln -sf /mnt/docker /var/lib/docker

# Discover what version of the OS we're running so we can set variables based on that.
source /etc/lsb-release

# Enable unattended use of apt-get.
export DEBIAN_FRONTEND=noninteractive

APT_SOURCES_DIR=/etc/apt/sources.list.d

update-repo() {
    for source in "$@"; do
        sudo apt-get update -qq \
            -o Dir::Etc::sourcelist="sources.list.d/${source}" \
            -o Dir::Etc::sourceparts="-" \
            -o APT::Get::List-Cleanup="0"
    done
}

# Packages that are installed on every worker host. Other packages
# that are needed to fulfill a particular host type's role should
# be installed by a job that needs them, the first time it runs.
DEFAULT_PACKAGES="
  python-pip
  git
  jq
  parallel
  zip
  openntpd
  moreutils"

# Tools for building .deb archives.
DEBIAN_BUILD_PACKAGES="
  default-jre
  debhelper
  quilt"

# Set up a couple of misc system settings...
initial_system_setup() {
  # Ensure that we can do git clones without strict host key checking
  cat <<EOF >> ~ubuntu/.ssh/config
Host *
        StrictHostKeyChecking no
EOF
  chown ubuntu.ubuntu ~ubuntu/.ssh/config
  apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 40976EAF437D05B5
  apt-key adv --recv-keys --keyserver keyserver.ubuntu.com BAD55AD940BBB133
  # Do an Apt-Get update so that later package installs can succeed
  apt-get -y -q update
}

prep_for_jenkins() {
  # Run Jenkins on the faster RAID storage
  JENKINS_HOME="/mnt/jenkins"  # Match the "Remote FS root" setting from the Jenkins EC2 Plugin
  mkdir -p $JENKINS_HOME && chown ubuntu:ubuntu $JENKINS_HOME

  # Tell well-behaved programs to put their output on the big drive
  TMPDIR=/mnt/tmp
  mkdir -p $TMPDIR
  chmod 1777 $TMPDIR
  cat >> /etc/profile << EOF
TMPDIR=$TMPDIR
export TMPDIR
EOF
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

    local HTTPS_SOURCES_LIST=https.sources.list

    # Install the apt-transport-s3 driver if it is missing
    dpkg --status apt-transport-s3 > /dev/null || install_packages apt-transport-s3
    apt-get update
}

install_packages() {
  # Install a list of Debian packages
  apt-get -y --force-yes -q install $*
}

install_jdk() {
    if [[ ! -f /tmp/jdk8.tar.gz ]]; then
      wget --continue --no-check-certificate -O /tmp/jdk8.tar.gz --header "Cookie: oraclelicense=a" 'https://edelivery.oracle.com/otn-pub/java/jdk/8u161-b12/2f38c3b165be4555a1fa6e98c45e0808/jdk-8u161-linux-x64.tar.gz'
    fi
    cd /tmp
    tar xfz jdk8.tar.gz
    rm -rf /usr/local/java/jdk1.8.0_161
    mv jdk1.8.0_161 /usr/local/java
    echo 'export JAVA_HOME=/usr/local/java' >> /home/ubuntu/.bash_profile
    echo 'export PATH=$PATH:$JAVA_HOME/bin' >> /home/ubuntu/.bash_profile
    update-alternatives --install /usr/bin/java java /usr/local/java/bin/java 1081
}

install_ruby() {
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
      gnupg2
      libffi-dev
      libgdbm-dev
      libssl-dev
      pkg-config
      zlib1g-dev"
  install_packages $RUBY_PACKAGES

  # Install gpg key for rvm
  su -l ubuntu -c bash -c "gpg2 --keyserver keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB"

  # Su back to the Ubuntu user and install RVM under it
  su -l ubuntu -c bash -c "\curl -sSL https://get.rvm.io | bash -s stable"
}

install_docker() {
  # Add the repository to your APT sources
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

  add-apt-repository \
       "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
       $(lsb_release -cs) \
       stable"

  # Install docker
  apt-get update
  install_packages docker-ce docker-ce-cli containerd.io

  # Ensure that Docker uses /mnt/docker for storage (so it doesn't fill up the
  # root volume). Also ensure that the docker socket file is owned by the
  # 'jenkins' group, allowing Jenkins to interact with it.
  cat << EOF >>  /etc/default/docker
TMPDIR=/mnt/tmp
DOCKER_TMPDIR=/mnt/tmp
DOCKER_OPTS="-g /mnt/docker -G ubuntu --storage-opt dm.basesize=20G"
EOF
  mkdir -p /mnt/docker
  set -e
  # See https://github.com/opencontainers/runc/issues/726
  echo 10240000000 > /proc/sys/kernel/keys/root_maxbytes
  echo 1024000 > /proc/sys/kernel/keys/root_maxkeys
  echo 1024000 > /proc/sys/kernel/keys/maxkeys
  echo 1024000 > /proc/sys/kernel/keys/maxbytes
  # Lastly, restart it now that we've reconfigured it.
  service docker restart
  
  for i in 1 2 3 4 5; do docker ps && break || sleep 5; done
  
  docker run \
    -e KEEP_IMAGES="hub.corp.nextdoor.com/dev-tools/nextdoor_db_9_4 hub.corp.nextdoor.com/dev-tools/atlas hub.corp.nextdoor.com/nextdoor/gnarfeed" \
    -v /var/run/docker.sock:/var/run/docker.sock:rw \
    -v /var/lib/docker:/var/lib/docker:rw \
    -d \
    --restart="unless-stopped" \
    meltwater/docker-cleanup:latest
  # Cleanup all nextdoor_app images after 30th every Sunday.
  echo "0 17 * * sun docker images -a | grep nextdoor_app | tail -n +30 | awk '{ print \$3 }' | xargs docker rmi -f" | crontab
  # Cleanup /tmp/pip-* older than an hour every hour.
  (crontab -l ; echo "0 * * * * find /tmp -name 'pip-*' -mmin +60 | xargs sudo rm -rf") | crontab -
  # Cleanup any tmp files in /home/ubuntu older than a half hour every half hour.
  (crontab -l ; echo "*/30 * * * * find /home/ubuntu/ -maxdepth 2 -name 'tmp.*' -mmin +30 | xargs sudo rm -rf") | crontab -
  # Cleanup all the build cache files older than an hour every hour.
  (crontab -l ; echo "0 * * * * find /mnt/tmp/.nextdoor-docker-cache/ -name 'tmp.*' -mmin +60 | xargs sudo rm -rf") | crontab -
  # Cleanup unused docker networks every 10 minutes that are older than 10 minutes.
  (crontab -l ; echo "*/10 * * * * docker network prune --force --filter until=10m") | crontab -
}

install_datadog_agent() {
    # Install the Datadog agent. The agent requires an API key which is expected
    # to be present in the shell environment as DATADOG_AGENT_API_KEY. If the
    # value is not present then inform stdout but do not fail the run.
    if [[ -z "${DATADOG_AGENT_API_KEY}" ]]; then
	echo "Optional envvar DATADOG_AGENT_API_KEY does not exist."
    else
	# PC1 == Puppet Collection 1 == most stable for this platform
	PUPPET_REPO_URI='https://apt.puppetlabs.com/puppet-release-trusty.deb'
	(cd /tmp &&
	  wget --no-check-certificate "${PUPPET_REPO_URI}" &&
	  dpkg -i puppet*.deb)

	set -e
	
	update-repo puppet.list
	apt-get install -y puppet-agent
	PATH=/opt/puppetlabs/puppet/bin:$PATH
	puppet module install datadog/datadog_agent --version 3.1.0
	puppet apply --verbose -e "

class { '::datadog_agent': 
  api_key => '${DATADOG_AGENT_API_KEY}',
  agent_version => '1:7.16.0-1',
  tags => ['devtools_group:ci', 'devtools_ci:jenkins'],
} ->

service { 'puppet':
  ensure => stopped,
  enable => false,
}
"
    fi
}

install_pip() {
    apt-get install -y python-dev build-essential python-virtualenv python3.5-venv
    #apt-get install -y python2.7
}

install_docker_tools() {
    pip install functools32
    curl -L "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
}

install_aws_cli() {
    pip install aws
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
    prep_for_jenkins
    create_apt_sources
    install_packages $DEFAULT_PACKAGES
    install_jdk
    install_packages $DEBIAN_BUILD_PACKAGES
    install_ruby
    install_docker
    install_datadog_agent
    install_pip
    install_docker_tools
    install_aws_cli
    sudo service postgresql stop || true
    # force an ntpd clock sync
    ntpd -s || true
}

main $*
