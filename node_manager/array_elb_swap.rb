#!/usr/bin/env ruby

# This script operates on two sets of ServerArrays and introduces the "add"
# version of the arrays to an ELB while removing the "remove" version of the
# arrays from the same ELB.
#
# Best use case for this script is a classical rollback scenario for two sets
# of arrays created by the deploy script.

require 'rubygems'
require 'json'

require File.join(File.expand_path(File.dirname(__FILE__)), 'defaults.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), 'get_logger.rb')
require File.join(File.expand_path(File.dirname(__FILE__)),
                  'get_right_client.rb')
require File.join(File.expand_path(File.dirname(__FILE__)), 'elb_manager.rb')

# Global logger
$log = get_logger()

DEFAULT_SLEEP = 300  # 5 minutes.

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
    :version_remove => nil,
    :version_add => nil,
    :sleep => DEFAULT_SLEEP
  }

  parser = OptionParser.new do|opts|
    opts.banner = "Usage: deploy.rb [options]"

    opts.on('-e', '--env ENV', 'Deployment environment string.') do |env|
      options[:env] = env;
    end

    opts.on('-o', '--version_remove VERSION',
            'Currently ELB-added version to be removed.') do |version|
      options[:version_remove] = version;
    end

    opts.on('-o', '--version_add VERSION',
            'Replacement version to be added.') do |version|
      options[:version_add] = version;
    end

    opts.on('-d', '--dryrun', 'Dryrun. Do not make changes.') do
      options[:dryrun] = true
      $log.info('Dryrun is on.  Not making any changes')
    end

    opts.on('-s', '--sleep NUM',
            'Override time to sleep ELB tasks. Default: %s seconds.' % DEFAULT_SLEEP) do |sleep|
      options[:sleep] = sleep.to_i
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
    puts parser.summarize()
    abort('env must be staging or prod.')
  end

  if not options[:json]
    abort('You must provide a JSON input file.')
  end

  if not options[:refresh_token]
    abort('You must specify a refresh token.')
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


def _remove_servers_from_elb(right_client, config, version, env, dryrun)
  $log.info('Removing each service from respecive ELB...')
  # Keep a list of update_elb tasks so we can check their status
  elb_tasks = []
  config.each do |service, params|
    server_array_name = get_server_array_name(
        env, params['region'], service, version)

    if params.has_key? 'elb_name'
      if params['elb_name'] != ''
        $log.info('Creating an "remove" task for service "%s"' % service)
        task = update_elb(dryrun, right_client, params['elb_name'],
                          server_array_name, env, 'remove')
        elb_tasks.push(task)
      end
    end
  end

  $log.info('Waiting for ELB "remove" tasks...')
  if not dryrun
    wait_for_elb_tasks(elb_tasks)
  end
  $log.info('ELB "remove" tasks completed!')
end



# Main function.
#
def main()
  args = parse_arguments()
  right_client = get_right_client(args[:oauth2_api_url],
                                  args[:refresh_token],
                                  args[:api_version],
                                  args[:api_url])

  config = parse_json_file(args[:json])

  #### Sanity Checks
  if args[:version_remove]
    # Check that the version is in the right format
    if args[:version_remove] !~ /.*-.{7}/
      abort('ERROR: version_remove does not match our release pattern')
    end
  end

  $log.info('Sanity Check: for the arrays with the "current" version exist')
  config.each do |service, params|
    old_server_array_name = get_server_array_name(
      args[:env], params['region'], service, args[:version_remove])

    old_elbs = find_server_array(right_client, old_server_array_name)
    if old_elbs.nil?
      abort('ERROR: Failed a sanity check: ' +
            'Could not find an array "%s".' % old_server_array_name)
    end
  end

  $log.info('Sanity Check: for the arrays with the "new" version exist')
  config.each do |service, params|
    old_server_array_name = get_server_array_name(
      args[:env], params['region'], service, args[:version_add])

    old_elbs = find_server_array(right_client, old_server_array_name)
    if old_elbs.nil?
      abort('ERROR: Failed a sanity check: ' +
            'Could not find an array "%s".' % old_server_array_name)
    end
  end

  $log.info('All sanity checks passed.')

  #### Add the new server arrays to ELBs
  tries = 3
  begin
    _add_servers_to_elb(right_client,
      config, args[:version_add], args[:env], args[:dryrun])
  rescue ELBTaskException
    $log.info('Some servers did not add themsleves to ELB.')

    tries -= 1
    if tries > 0 
      $log.info('Retrying...')
      retry
    end
    raise  # Re-raise the same exception.
  end

  if args[:dryrun]
    $log.info('DRY RUN -- skipping sleep')
  else
    $log.info('Sleeping for %s seconds to make sure the ELB has registered the instances...' % args[:sleep])
    sleep(args[:sleep])
  end

  #### Remove the old instances from the ELB
  tries = 3
  begin
    _remove_servers_from_elb(right_client,
      config, args[:version_remove], args[:env], args[:dryrun])
  rescue ELBTaskException
    $log.info('Some servers did not remove themsleves from ELB.')

    tries -= 1
    if tries > 0 
      $log.info('Retrying...')
      retry
    end
    raise  # Re-raise the same exception.
  end
end

#
# Program entry.
#
if __FILE__ == $0
  main()
end
