Public Ops Tools
================
A bunch of operational scripts.

Set up gerrit code review
=========================

Step 1
------
Place the following lines into ~/.ssh/config:

    Host review
        Hostname review.yourcompany.com
        Port 29418
        User <YOUR LDAP USERNAME>

Then verify that you can connect to Gerrit:

    $ ssh review.yourcompany.com
        ****    Welcome to Gerrit Code Review    ****

    Hi YOURNAME, you have successfully connected over SSH.

    Unfortunately, interactive shells are disabled.
        To clone a hosted Git repository, use:

    git clone ssh://yourname@review.yourcompany.com:29418/REPOSITORY_NAME.git

    Connection to review.yourcompany.com closed.

Step 2
------

Install and configure git-change:

    $ sudo easy_install pip
    $ sudo pip install git-change

Step 3
------

Clone and configure the repo:

    $ git clone review:public-ops-tools
    $ cd public-ops-tools
    $ etc/configure-repository.sh
