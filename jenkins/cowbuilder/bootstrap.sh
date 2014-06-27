#!/bin/bash -x
#
# = About
#
# This is a super basic set of files used to configure Cowbuilder on a build
# server and build its base image. The base image build takes 2-3 minutes and
# needs to be done once before any builds with Cowbuilder can occur.
#
# == Usage
#
#   MASTER="https://raw.githubusercontent.com/Nextdoor/public-ops-tools/master"
#   BASE="${MASTER}/jenkins/cowbuilder"
#   FILES="bootstrap.sh cowbuilderrc finish.sh"
#   for file in $FILES; do
#     curl --silent --insecure -O ${BASE}/${FILE}
#   done
#   sudo bootstrap.sh
#
DIST=precise ARCH=amd64 /usr/sbin/cowbuilder --create --configfile cowbuilderrc
DIST=precise ARCH=amd64 /usr/sbin/cowbuilder --execute --save-after-exec --configfile cowbuilderrc -- ./finish.sh
