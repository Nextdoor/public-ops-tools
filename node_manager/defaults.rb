# How many seconds we wait checking the add/remove ELB task before giving up
$RS_TIMEOUT = 300

# These are the RightScale 'RightScripts' that add or remove SAs from ELBs.
# They're unique to our accounts
# Add - Connect instance (SA) to ELB
# Remove - Disconnect instance (SA) from ELB

$RIGHT_SCRIPT = {
  'add'    => {
    'staging' => '/api/right_scripts/438671001',
    'prod'    => '/api/right_scripts/232971001' },
  'remove' => {
    'staging' => '/api/right_scripts/396277001',
    'prod'     => '/api/right_scripts/232972001' }
}

$DEFAULT_NUM_INSTANCES = 3
$DEFAULT_API_URL = 'https://my.rightscale.com'
$DEFAULT_API_VERSION = '1.5'
$DEFAULT_ENV = 'staging'
$DEFAULT_REGION = 'uswest2'
$DEFAULT_SERVICE_NAME = 'servicename'
$DEFAULT_OAUTH2_API_URL = 'https://my.rightscale.com/api/oauth2'
$DEFAULT_OAUTH_TIMEOUT = 15
