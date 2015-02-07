#!/bin/bash -e
# Create a Jenkins slave to build, test, and deploy Django apps on ubuntu 12.04.
#
# Call the script like this:
# 
# export GITHUB="https://raw.githubusercontent.com/Nextdoor/public-ops-tools/master/" 
# export AWS_ACCESS_KEY_ID=<something> 
# export AWS_SECRET_ACCESS_KEY=<something> 
# curl -q --insecure $GITHUB/jenkins/executors/django_cowbuilder_provision.sh | /bin/bash

# apt-transport-https accessed repos
export HTTPS_REPOS="
deb https://s3.amazonaws.com/cloud.nextdoor.com/repos/precise stable main\n
deb https://s3.amazonaws.com/cloud.nextdoor.com/repos/precise unstable main\n"

# apt-transport-s3 accessed repos
export S3_REPOS="
deb s3://${AWS_ACCESS_KEY_ID}:[${AWS_SECRET_ACCESS_KEY}]@s3.amazonaws.com/cloud.nextdoor.com/debian_repos/precise/ stable/\n
deb s3://${AWS_ACCESS_KEY_ID}:[${AWS_SECRET_ACCESS_KEY}]@s3.amazonaws.com/cloud.nextdoor.com/debian_repos/precise/ unstable/\n
deb s3://${AWS_ACCESS_KEY_ID}:[${AWS_SECRET_ACCESS_KEY}]@s3.amazonaws.com/cloud.nextdoor.com/debian_repos/melissadata/ stable/\n
deb s3://${AWS_ACCESS_KEY_ID}:[${AWS_SECRET_ACCESS_KEY}]@s3.amazonaws.com/cloud.nextdoor.com/debian_repos/melissadata/ unstable/\n"

# Our Boot Script
BOOTSCRIPT="${GITHUB}/jenkins/ec2_bootstrap.sh"

# Execute the bootstrap script, preserving the environment variables above.
curl -q --insecure $BOOTSCRIPT | sudo -E /bin/bash

# Enable login to the slave by appending public keys to this file from the Jenkins config.
mkdir -m 755 -p ~/.ssh
echo "$AUTHORIZED_KEYS" > ~/.ssh/authorized_keys
chmod 400 ~/.ssh/authorized_keys

set -x
# Move /tmp and /var/cache to the big partition.
for DIR in /tmp /var/cache; do
    [[ -e /mnt/$DIR ]] && continue
    echo "Bind-mount $DIR to /mnt$DIR"
    sudo mv $DIR /mnt
    sudo mkdir -p $DIR
    sudo mount --bind /mnt/$DIR $DIR
done

# Create a sentinel file so the first continuous build will
# install the Debian packages that the builds need.
touch /tmp/FIRST_TIME
touch /tmp/FIRST_TIME_GO
touch /tmp/FIRST_TIME_GO_PHOTO

## COWBUILDER SETUP
BASE="${GITHUB}/jenkins/cowbuilder"
FILES="bootstrap.sh cowbuilderrc finish.sh"
for file in $FILES; do
  curl --silent --insecure -O ${BASE}/${file}
done
time sudo /bin/bash -x bootstrap.sh

# Use the '-y' flag with apt-get (for non-interactive installs)
[[ ! -f /etc/apt/apt.conf.d/30apt_assume_yes.conf ]] &&
    sudo su root -c "cat > /etc/apt/apt.conf.d/30apt_assume_yes.conf" << EOF
APT {
       Get {
                Assume-Yes "true";
        };
};
EOF
