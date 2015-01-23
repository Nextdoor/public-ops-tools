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

# Move /tmp and /var to the big partition.
for DIR in /tmp /var; do
    [[ -e /mnt/$DIR ]] && continue
    echo "Bind-mount $DIR to /mnt$DIR"
    sudo mv $DIR /mnt$DIR
    sudo mkdir $DIR
    echo "/mnt$DIR	$DIR	none	bind	0	0" | sudo tee -a /etc/fstab
    sudo mount $DIR
done

# Create a sentinel file so the first continuous build will
# install the Debian packages that the builds need.
touch /tmp/FIRST_TIME

## COWBUILDER SETUP
BASE="${GITHUB}/jenkins/cowbuilder"
FILES="bootstrap.sh cowbuilderrc finish.sh"
for file in $FILES; do
  curl --silent --insecure -O ${BASE}/${file}
done
time sudo /bin/bash -x bootstrap.sh

## CUSTOM DJANGO STUFF

# Uninstall NodeJS (installed on default build systems).
# Our node-nextdoor package conflicts with it.
# TODO: Fix that!
time sudo DEBIAN_FRONTEND=noninteractive apt-get -y --force-yes -q purge nodejs

# Use the '-y' flag with apt-get (for non-interactive installs)
sudo cat > /etc/apt/apt.conf.d/nextdoor.conf << EOF
APT {
       Get {
                Assume-Yes "true";
        };
};
EOF

mkdir -p ~/.ssh

# Matt Terry's key
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCps4u1tFiCjNa6k9RMeOS4aAjOmpEPOmv6ljoSLJIaowLP9Jf2YdqdVNflgiSFE1cwpXPE8KBAatcfss2y386R93XJLHiYrxitIjzHB2IVXRoxKBbHtEb5oPLGid/WeeUjMKESZYpnEZwk4jU2wNTJt0ncy8GOmbIyWSgX+QVTVKb26VaVWGkUYVsM0qr8J/y0eCX8n7Me8l2yNTbY2PF7POTemWyqK6fHxXxCDvy7LYXYXhHXPOxqGcz6KzcTvGIdgm1FlLQqpTk/62yGPGMQ6UrOckKvOMZt0unwdDukiFhiSjS2OkmOCiBY8dz9iHwvGi0AM0oPbJwgP1mxxZgF mrterry@mrterry-dev.localdomain" >> ~/.ssh/authorized_keys

# Charles' key
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC+PMBKRwRV3LtpH69XG9mmM5qTDQGa6STC1+/yd4BJsNN+gfJHdw7ULMwN4UtTLX+BJXPOQ4maE7F1dSjkRLM8pGOdReCM1NiJFKY9ECTnaNaJ5GnoNqbAGkKyGC85Ev8sXJkPo7rrO5VSFOlURnwvtLDeV2ARRh0uFEVX2/dogGeSUP+IUKdY1HnJQIcdKV1JgPMFO6JMCL/yaPEgQF5eM5ZBjWXNxfCQQhpC25xTU6f86np2kICV0etIudyseod+wyLUuNk/sDvSpim8xzohT2XMFSHmvFTx10FqwgQ6Ol20lba3qiko5kRwUo3mbFxTw50r0cGtxkglrVgjLzoB charlesmclaughlin@charles.local" >> ~/.ssh/authorized_keys

# Chuck's key
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCmMToxbTYqV7u8SIDNUhICSchcI04n066hdLhfMtnJItpG5KaRulM6wQx/8bmnqa+/fu+tUBlIXyo0yodDBYfSMXjKTMBVhZTVOmhITpAA4Slo88Bg7l90GfRy5TtKjx7UM2w13wp7BkHnwKidUPeFr1Cfm4GcrvjkeWRbf8SOpC0aqthYEu9ljFK3hryzc4ttdAugQ+u2GaJD9haxuZ5xHQzTFZadEh7ALWKYUae4RczB4n6dFRbDEUNYjbtZ+iNryxfhrU6KDGaeHwiez0umDUdZpzGjjCm0le13S35Y3hwRbXVzcG40YROWUfZ9kj0J7P9wxPZAthjHWbn3S4c1 chuck@2014-05-22" >> ~/.ssh/authorized_keys

chown ubuntu ~/.ssh/authorized_keys
chmod 0600 ~/.ssh/authorized_keys
