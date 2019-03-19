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
  openntpd"

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

install_packagecloud_gpg_key() {
    cat << EOF | apt-key add -
-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v1.4.11 (GNU/Linux)

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
sA==
=H60S
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
  apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 40976EAF437D05B5
  apt-key adv --recv-keys --keyserver keyserver.ubuntu.com BAD55AD940BBB133
  install_nextdoor_gpg_key
  install_packagecloud_gpg_key
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
    if [[ ! -f $APT_SOURCES_DIR/$HTTPS_SOURCES_LIST ]]; then
        # Install the Nextdoor public repos
        cat > $APT_SOURCES_DIR/$HTTPS_SOURCES_LIST << EOF
deb https://s3.amazonaws.com/cloud.nextdoor.com/repos/precise stable main
deb https://s3.amazonaws.com/cloud.nextdoor.com/repos/precise unstable main
EOF
        update-repo $HTTPS_SOURCES_LIST
    fi

    # Install the apt-transport-s3 driver if it is missing
    dpkg --status apt-transport-s3 > /dev/null || install_packages apt-transport-s3

    # Configure for the Nextdoor apt repo
    cat > $APT_SOURCES_DIR/packagecloud.list << EOF
deb https://${PROD_PACKAGECLOUD_TOKEN}:@packagecloud.io/nextdoor/prod/any/ any main 
deb https://${PROD_PACKAGECLOUD_TOKEN}:@packagecloud.io/nextdoor/prod/ubuntu/ precise main 
deb https://${ENG_PACKAGECLOUD_TOKEN}:@packagecloud.io/nextdoor/staging/any/ any main 
deb https://${ENG_PACKAGECLOUD_TOKEN}:@packagecloud.io/nextdoor/staging/ubuntu/ precise main 
EOF
    update-repo packagecloud.list

    # Configure apt pinning
    cat > /etc/apt/preferences.d/packagecloud.pref <<EOF
Explanation: repos: packagecloud
Package: *
Pin: origin packagecloud.io
Pin-Priority: 1002
EOF
    apt-add-repository ppa:git-core/ppa
    add-apt-repository "deb http://us.archive.ubuntu.com/ubuntu/ precise-backports main restricted universe multiverse"
    add-apt-repository ppa:jonathonf/python-2.7
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

# Use nodesource repos to install NodeJS & sinopia.
install_npm_proxy_cache() {
  # Ugh - but this is the way we install Node elsewhere.
  curl -sL https://deb.nodesource.com/setup_6.x | bash -
  apt-get install -y nodejs
  # Install sinopia globally and set up a boot-time service
  npm install -g forever forever-service sinopia
  mkdir -p /mnt/sinopia
  forever-service install --start --script /usr/bin/sinopia -f ' --workingDir /mnt/' sinopia
}

install_docker() {
  # Add the repository to your APT sources
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

  add-apt-repository \
       "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
       $(lsb_release -cs) \
       stable"

  apt-get install docker-ce docker-ce-cli containerd.io

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
  (crontab -l ; echo "0 * * * * find /mnt/tmp/.nextdoor-docker-cache/ -name 'tmp.*' -mmin +60 | xargs sudo rm -rf") | crontab -l
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

install_datadog_agent() {
    # Install the Datadog agent. The agent requires an API key which is expected
    # to be present in the shell environment as DATADOG_AGENT_API_KEY. If the
    # value is not present then inform stdout but do not fail the run.
    if [[ -z "${DATADOG_AGENT_API_KEY}" ]]; then
	echo "Optional envvar DATADOG_AGENT_API_KEY does not exist."
    else
	# PC1 == Puppet Collection 1 == most stable for this platform
	PUPPET_REPO_URI='https://apt.puppetlabs.com/puppetlabs-release-pc1-precise.deb'
	(cd /tmp &&
	  wget --no-check-certificate "${PUPPET_REPO_URI}" &&
	  dpkg -i puppetlabs*.deb)

	set -e
	
	update-repo puppetlabs-pc1.list
	apt-get install -y puppet-agent
	PATH=/opt/puppetlabs/puppet/bin:$PATH
	puppet module install datadog/datadog_agent --version 1.12.1
	puppet apply --verbose -e "

class { '::datadog_agent': 
  api_key => '${DATADOG_AGENT_API_KEY}',
  bind_host => '0.0.0.0',
  log_level => 'error',
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
    apt-get install -y python2.7
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
    install_npm_proxy_cache
    install_pip
    install_docker_tools
    install_aws_cli
    # if [[ -n "$PREPARE_COWBUILDER" ]]; then prepare_cowbuilder; fi
    sudo service postgresql stop || true
    # force an ntpd clock sync
    ntpd -s || true
}

main $*
