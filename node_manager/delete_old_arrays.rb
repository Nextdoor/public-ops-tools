#!/usr/bin/env ruby

# This script deletes all arrays that match the old_build_version by
# 1) Check SQS for queue
# 2) disabling the array
# 3) termianting all instances on that array
# 4) deleting the array

$file_dir = File.expand_path(File.dirname(__FILE__))

require File.join($file_dir, 'defaults.rb')
require File.join($file_dir, 'get_logger.rb')
require File.join($file_dir, 'get_right_client.rb')
require File.join($file_dir, 'elb_manager.rb')
require File.join($file_dir, 'node_manager.rb')

# Global logger
$log = get_logger()

# Parse command line arguments. Many variables below come from defaults.rb
def parse_arguments()
  options = {
    :api_url => $DEFAULT_API_URL,
    :api_version => $DEFAULT_API_VERSION,
    :aws_access_key => nil,
    :aws_secret_access_key => nil,
    :dryrun => nil,
    :env => $DEFAULT_ENV,
    :oauth2_api_url => $DEFAULT_OAUTH2_API_URL,
    :old_build_version => nil,
    :refresh_token => nil,
    :region => $DEFAULT_REGION,
  }

  parser = OptionParser.new do|opts|
    opts.banner = "Usage: deploy.rb [options]"

    opts.on('-a', '--aws_access_key ACCESS_KEY',
            'AWS_ACCESS_KEY_ID.') do |aws_access_key|
      options[:aws_access_key] = aws_access_key;
    end

    opts.on('-k', '--aws_secret_access_key SECRET',
            'AWS_SECRET_ACCESS_KEY.') do |aws_secret_access_key|
      options[:aws_secret_access_key] = aws_secret_access_key;
    end

    opts.on('-e', '--env ENV', 'Deployment environment string.') do |env|
      options[:env] = env;
    end

    opts.on('-o', '--old_build_version [=OLD_BUILD_VERSION]',
            'Current install version string.') do |old_build_version|
      options[:old_build_version] = old_build_version;
    end

    opts.on('-d', '--dryrun', 'Dryrun. Do not make changes.') do
      options[:dryrun] = true
      $log.info('Dryrun is on.  Not making any changes')
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

    opts.on('-r', '--region REGION', 'AWS Region.') do |region|
      options[:region] = region;
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

  if not options[:refresh_token]
    puts parser.summarize()
    abort('You must specify a refresh token.')
  end

  if options[:old_build_version].nil?
    puts parser.summarize()
    abort('--old_build_version is required.')
  end

  if options[:aws_access_key].nil?
    puts parser.summarize()
    abort('Thou shalt provide the AWS access key id!')
  end

  if options[:aws_secret_access_key].nil?
    puts parser.summarize()
    abort('Thou shalt provide the AWS secret access key!')
  end

  return options
end

# Main function.
#
def main()
  args = parse_arguments()
  right_client = get_right_client(args[:oauth2_api_url],
                                  args[:refresh_token],
                                  args[:api_version],
                                  args[:api_url])

  old_short_version = args[:old_build_version]
  #### Checking the SQS queue

  while not queues_empty?(args[:aws_access_key], args[:aws_secret_access_key],
                          args[:env], args[:region], old_short_version)
    $log.info('Waiting for SQS "%s" to become empty...' % old_short_version)
    if args[:dryrun]
        $log.info('DRY RUN -- skipping the wait.')
        break
    end
    sleep 60
  end
  $log.info('SQS queue is empty')

  #### Delete arrays

  $log.info('Searching for all arrays matching %s' % old_short_version)
  all_arrays = find_server_arrays(right_client, old_short_version)

  # This issues an async task. We'll check the count later.
  for array in all_arrays
      if not args[:dryrun]
          $log.info('Terminating array %s' % array.name)

          # Disable autoscaling... this happens syncronously
          array.update({ :server_array => { :state => 'disabled' }})

          # Terminate every server instance in the array.
          array.multi_terminate(terminate_all=true)
      else
          $log.info('Would have terminated array %s' % array.name)
      end
  end

  # Wait for all arrays to be empty before deleting them.
  $log.info('Checking if arrays are empty...')
  while all_arrays.count > 0

    there_were_changes = false  # skip sleep when there were changes.

    for array in all_arrays
        count = array.instances_count
        $log.info('Array %s has %s instances.' % [array.name, count])
        if count == 0
            if args[:dryrun]
                $log.info('Would have deleted the entire array...')
            else
                $log.info('Deleteing the entire array...')
                array.destroy
                there_were_changes = true
            end
        end
    end
    # Once an array is destroyed we shouldn't be able to "find" it -- refresh
    # the list here. When `all_arrays` is empty, the loop ends.
    if not args[:dryrun]
        sleep 60 unless there_were_changes
        all_arrays = find_server_arrays(right_client, old_short_version)
    elsif
        all_arrays = []  # Faking for dry run
        $log.info('Dry run -- pretending that all arrays have been deleted.')
    end
  end

  $log.info("Done!")
end

#
# Program entry.
#
if __FILE__ == $0
  main()
end
