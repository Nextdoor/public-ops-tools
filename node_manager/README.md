# Deploy
This script uses Node Manager and ELB Manager to fully orchestrate deploys.

## Node Manager
This script creates or deletes a server array via the RightScale API.

## ELB Manager
This script adds entire server arrays to ELBs via the RightScale API.

### Setup

    rake install

### Running Tests

    rake test

### Examples

Create array

    ./node_manager.rb --refresh_token XXX --tmpl_server_array XXX --build_url https://jenkinshost/view/job/.../lastSuccessfulBuild/artifact/....dsc --oauth2_api_url https://us-3.rightscale.com/api/oauth2

Delete array

    ./node_manager.rb --refresh_token XXX --tmpl_server_array XXX --build_url https://jenkinshost/view/job/.../lastSuccessfulBuild/artifact/....dsc --oauth2_api_url https://us-3.rightscale.com/api/oauth2 --delete true

Add to ELB

    ./elb_manager.rb --add --refresh_token XXX --oauth2_api_url https://us-3.rightscale.com/api/oauth2 --server_array MY_ARRAY --elb MY_ELB

Remove from ELB

    ./elb_manager.rb --remove --refresh_token XXX --oauth2_api_url https://us-3.rightscale.com/api/oauth2 --server_array MY_ARRAY --elb MY_ELB --remove true
