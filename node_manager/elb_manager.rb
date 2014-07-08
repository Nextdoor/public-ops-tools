#!/usr/bin/ruby
#
# Command to add and remove entire RightScale server arrays to or from ELBs.
# Intended for red/black deploys.  For instance
# Use node_manager.rb to clone a new server array with upgraded packages
# Use this script to add the entire new array to an an existing ELB
# Use this script to remove the old instances in the old array from the ELB
# After testing, use node_manager.rb to remove the old server array

require 'optparse'
require './node_manager'

# These are the RightScale 'RightScripts' that add or remove from ELBs.
# They're unique to our accounts
# Add - Connect instance to ELB
# Remove - Disconnect instance from ELB
$RS_ADD = {
  'staging' => '/api/right_scripts/438671001',
  'prod'    => '/api/right_scripts/232971001'
}
$RS_REMOVE = {
  'staging' => '/api/right_scripts/396277001',
  'prod' => '/api/right_scripts/232972001'
}

# Parse command line arguments.  Some defaults come from node_manager.rb
def parse_arguments()
  options = {
    :add => false,
    :remove => false,
    :env => $DEFAULT_ENV,
    :server_array => nil,
    :elb => nil,
    :oauth2_api_url => $DEFAULT_OAUTH2_API_URL,
    :refresh_token => nil,
    :api_version => $DEFAULT_API_VERSION,
    :api_url => $DEFAULT_API_URL,
    :dryrun => false
  }

  parser = OptionParser.new do|opts|
    opts.banner = "Usage: elb_manager.rb [options]"

    opts.on('-r', '--remove', 'Remove server array from a ELB.') do
      options[:remove] = true
    end

    opts.on('-a', '--add', 'Add server array to a ELB.') do
      options[:add] = true
    end

    opts.on('-e', '--env ENV', 'Deployment environment.') do |env|
      options[:env] = env;
    end

    opts.on('-s', '--server_array SERVER_ARRAY_NAME',
            'Server array name to add or remove from ELB.') do |server_array|
      options[:server_array] = server_array
    end

    opts.on('-l', '--elb ELB_NAME',
            'ELB name to add or remove server array to or from.') do |elb|
      options[:elb] = elb
    end

    opts.on('-u', '--api_url API_URL', 'RightScale API URL.') do |api_url|
      options[:api_url] = api_url
    end

    opts.on('-v', '--api_version API_VERSION',
            'RightScale API Version.') do |api_version|
      options[:api_version] = api_version
    end

    opts.on('-t', '--refresh_token TOKEN',
            'The refresh token for RightScale OAuth2.') do |refresh_token|
      options[:refresh_token] = refresh_token
    end

    opts.on('-o', '--oauth2_api_url URL',
            'RightScale OAuth2 URL.') do |oauth2_api_url|
      options[:oauth2_api_url] = oauth2_api_url
    end

    opts.on('-d', '--dryrun', 'Dryrun. Do not update ELB.') do
      options[:dryrun] = true
    end
  end

  parser.parse!

  if options[:add] and options[:remove]
    abort('Add and remove are mutually exclusive.')
  end

  if not options[:add] and not options[:remove]
    abort('You must specify an action, --add or --remove.')
  end

  if not options[:server_array] or not options[:elb]
    abort('You must specify a server array and ELB to operate on.')
  end

  if not options[:refresh_token]
    abort('You must specify a refresh token.')
  end

  if not options[:env] == 'staging' and options[:env] == 'prod'
    abort('env must be staging or prod.')
  end

  return options
end

# Add or remove all instances of a server array to an ELB.
#
# * *Args*    :
#   - +server_array+ -> Server array name to add or remove.
#   - +elb+ -> ELB name to add to or remove from.
#   - +action+ -> Which action to perform, 'add' or 'remove'
#
def update_elb(right_client, elb, server_array, right_script, action)
  if action == 'add'
#    right_script = $RS_ADD[args[:env]]
    pre_msg   = 'Adding %s to %s'
    post_msg  = 'SUCCESS. Added %s to %s'
  elsif action == 'remove'
#    right_script = $RS_REMOVE[args[:env]]
    pre_msg  = 'Removing %s from %s'
    post_msg = 'SUCCESS. Removed %s from %s'
  else
    abort('Action must be add or remove.')
  end

  $log.info('Looking for server_array %s.' % server_array)
  server_array = find_server_array(:right_client => right_client,
                                   :server_array_name => server_array)

  $log.info(pre_msg % [server_array, elb])
#  if args[:dryrun]
#    $log.info('Dry run mode. Not operating on the ELB.')
#  else
    task = server_array.multi_run_executable(:right_script_href => right_script,
                                             :inputs => {'ELB_NAME' => "text:%s" % elb})

    while not task.show.summary.include? 'completed'
      $log.info('Waiting for add task to complete (%s).' % task.show.summary)
      sleep 1

      if task.show.summary.include? 'failed'
        abort('FAILED.  RightScript task failed!')
      end
    end
#  end

  $log.info(post_msg % [server_array, elb])
end

# Main function.
#
def main()
  # Parse command line arguments
  options = parse_arguments()

  if options[:add]
    update_elb(options, 'add')
  end

  if options[:remove]
    update_elb(options, 'remove')
  end
end

#
# Program entry.
#
if __FILE__ == $0
  main()
end
