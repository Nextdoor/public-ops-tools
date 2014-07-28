#! /usr/bin/env ruby

# This script uses node_manager and elb_manager to deploy full environments.
# Given a set of template server arrays and ELBs in JSON input, we clone the
# server arrays to create new ones.  Then we add the new server arrays to the
# existing ELBs, and remove the old server arrays from the ELBs.
# We perform these operations in threads, so we can run operations
# concurrently.

require 'rubygems'
require 'json'

require File.join(File.expand_path(File.dirname(__FILE__)), 'defaults.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), 'get_logger.rb')
require File.join(File.expand_path(File.dirname(__FILE__)),
                  'get_right_client.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), 'elb_manager.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), 'node_manager.rb')

# Global logger
$log = get_logger()

# Parse command line arguments. Many variables below come from defaults.rb
def parse_arguments()
  options = {
    :json => nil,
    :oauth2_api_url => $DEFAULT_OAUTH2_API_URL,
    :refresh_token => nil,
    :api_version => $DEFAULT_API_VERSION,
    :api_url => $DEFAULT_API_URL,
    :dryrun => nil,
    :env => $DEFAULT_ENV,
    :build_url => nil,
    :old_build_version => nil,
    :sleep => 360
  }

  parser = OptionParser.new do|opts|
    opts.banner = "Usage: deploy.rb [options]"

    opts.on('-e', '--env ENV', 'Deployment environment string.') do |env|
      options[:env] = env;
    end

    opts.on('-b', '--build_url BUILD_URL',
            'Jenkins Build URL for service package.') do |build_url|
      options[:build_url] = build_url;
    end

    opts.on('-o', '--old_build_version [=OLD_BUILD_VERSION]',
            'Current install version string.') do |old_build_version|
      options[:old_build_version] = old_build_version;
    end

    opts.on('-d', '--dryrun', 'Dryrun. Do not make changes.') do
      options[:dryrun] = true
      $log.info('Dryrun is on.  Not making any changes')
    end

    opts.on('-s', '--sleep NUM', 'Time to sleep between add/remove tasks to/from ELBs') do |sleep|
      options[:sleep] = sleep
    end

    opts.on('-j', '--json (FILE|-)',
            'File or STDIN of JSON - containing server array and ELB IDs.') do |json|
      options[:json] = json
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

  end

  parser.parse!

  if options[:env] != 'staging' and options[:env] != 'prod'
    abort('env must be staging or prod.')
  end

  if not options[:json]
    abort('You must provide a JSON input file.')
  end

  if not options[:refresh_token]
    abort('You must specify a refresh token.')
  end

  if options[:build_url].nil?
    abort('--build_url is required.')
  end

  return options
end

# Parse provided JSON file and return output
def parse_json_file(fname)
  if fname == '-'  # Expect stdin
      json = ARGF.read
  else
      file = open(fname)
      json = file.read
  end
  return JSON.parse(json)
end


def _add_servers_to_elb(right_client, config, version, env, dryrun)
  $log.info('Adding each service to respecive ELB...')
  # Keep a list of update_elb tasks so we can check their status
  elb_tasks = []
  config.each do |service, params|
    server_array_name = get_server_array_name(
        env, params['region'], service, version)

    if params.has_key? 'elb_name'
      if params['elb_name'] != ''
        $log.info('Creating an "add" task for service "%s"' % service)
        task = update_elb(dryrun, right_client, params['elb_name'],
                          server_array_name, env, 'add')
        elb_tasks.push(task)
      end
    end
  end

  $log.info('Waiting for ELB "add" tasks...')
  if not dryrun
    wait_for_elb_tasks(elb_tasks)
  end
  $log.info('ELB "add" tasks completed!')
end


# Main function.
#
def main()
  args = parse_arguments()
  right_client = get_right_client(args[:oauth2_api_url],
                                  args[:refresh_token],
                                  args[:api_version],
                                  args[:api_url])

  release_version = get_release_version(args[:build_url])
  short_version = get_short_version(release_version)

  config = parse_json_file(args[:json])

  $log.info('Deploy URL: %s' % args[:build_url])
  $log.info('Will deploy new arrays: %s' % config.keys.join(', '))
  $log.info('Old deployed version is: %s' % args[:old_build_version])

  #### Sanity Checks
  if args[:old_build_version]

    # Check that the version is in the right format
    if args[:old_build_version] !~ /.*-.{7}/
      abort('ERROR: old_build_version does not match our release pattern')
    end

    # Check that one of the arrays with this version already exists
    service = config.first[0]
    params = config.first[1]
    old_server_array_name = get_server_array_name(
      args[:env], params['region'], service, args[:old_build_version])

    old_elbs = find_server_array(right_client, old_server_array_name)
    if old_elbs.nil?
      abort('ERROR: Failed a sanity check: ' +
            'Could not find an array "%s".' % old_server_array_name)
    end
  end

  #### Create new server arrays

  # Keep a list of newly created server arrays so we can check if they have
  # running instances. Each element is another list/tuple of the array
  server_arrays = []

  config.each do |service, params|
    $log.info('Booting new instances for %s...' % service)

    server_array_name = get_server_array_name(
        args[:env], params['region'], service, short_version)

    if not args[:dryrun]
      new_array = clone_server_array(
        args[:dryrun], right_client,
        params['tmpl_server_array'], server_array_name,
        release_version,
        service, args[:env], params['region'])

     server_arrays.push(new_array)
    end
  end

  while true
    operational_array_count = 0
    unhealthy_arrays = []
    for server_array in server_arrays
      # checks if the server array has the min number of operational instances
      if min_instances_operational?(server_array)
        operational_array_count += 1
      else
        unhealthy_arrays.push(server_array.name)
      end
    end

    # Break if all server arrays have the min number of operational instances
    break if operational_array_count == server_arrays.length

    $log.info("Still waiting for %s" % unhealthy_arrays.join(','))
    sleep 60
  end
  $log.info('All needed arrays have booted.')


  #### Add the new server arrays to ELBs
  3.times { |run|
    begin
      _add_servers_to_elb(right_client, config, short_version, args[:env], args[:dryrun])
    rescue ELBTaskException
      $log.info('Some servers did not add themsleves to ELB.')

      if (run + 1) == 3
        abort('3rd time was not the charm. Aborting.')
      end

      $log.info('Rerunning...')
    else
      break
    end
  }


  #### Remove the old instances from the ELB
  if args[:old_build_version] != nil and args[:old_build_version] != ''
    # We can't easily check Multi-Run Executables status
    # So we wait 5 minutes before removing the old instances from the ELBs
    $log.info("Sleeping for #{args[:sleep]} seconds waiting for ELBs add tasks, just to be safe...")
    sleep Integer(args[:sleep])

    # Init the list of tasks
    elb_tasks = []

    config.each do |service, params|
      old_server_array_name = get_server_array_name(
        args[:env], params['region'], service, args[:old_build_version])

      if params.has_key? 'elb_name'
        if params['elb_name'] != ''
          $log.info('Creating an "remove" task for service "%s"' % service)
          task = update_elb(args[:dryrun], right_client, params['elb_name'],
                            old_server_array_name, args[:env], 'remove')
          elb_tasks.push(task)
        end
      end
    end

    $log.info('Waiting for ELB "remove" tasks...')
    if not args[:dryrun]
      wait_for_elb_tasks(elb_tasks)
    end
    $log.info('ELB "remove" tasks completed!')

    $log.info("Done!")
  end
end

#
# Program entry.
#
if __FILE__ == $0
  main()
end
