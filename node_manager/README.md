# Deploy
This script uses Node Manager and ELB Manager to fully orchestrate deploys.

## Node Manager
This script creates or deletes a server array via the RightScale API.

## ELB Manager
This script adds entire server arrays to ELBs via the RightScale API.

### Setup
RVM is recommended, but we're bound to Ruby 1.8.x.

 rvm install ruby-1.8.7-head
 rvm use ruby-1.8.7-head
 rvm gemset create node_manager
 rvm gemset use node_manager

Don't use bundle.  Instead, see the Gemfile for more info.

### Running Tests

    rake test
    rake spec

### Examples

Create array

    ./node_manager.rb --refresh_token XXX --tmpl_server_array XXX --build_url https://jenkinshost/view/job/.../lastSuccessfulBuild/artifact/....dsc --oauth2_api_url https://us-3.rightscale.com/api/oauth2

Delete array

    ./node_manager.rb --refresh_token XXX --tmpl_server_array XXX --build_url https://jenkinshost/view/job/.../lastSuccessfulBuild/artifact/....dsc --oauth2_api_url https://us-3.rightscale.com/api/oauth2 --delete true

Add to ELB

    ./elb_manager.rb --add --refresh_token XXX --oauth2_api_url https://us-3.rightscale.com/api/oauth2 --server_array MY_ARRAY --elb MY_ELB

Remove from ELB

    ./elb_manager.rb --remove --refresh_token XXX --oauth2_api_url https://us-3.rightscale.com/api/oauth2 --server_array MY_ARRAY --elb MY_ELB --remove true

Deploy

    ./deploy.rb --json test.json --refresh_token XXX --build_url https://jenkinshost/view/job/.../lastSuccessfulBuild/artifact/....dsc --old_build_url https://jenkinshost/view/job/.../lastSuccessfulBuild/artifact/....dsc --env staging
