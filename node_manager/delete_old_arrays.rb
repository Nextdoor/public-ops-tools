#! /usr/bin/env ruby

# This script uses node_manager and elb_manager to delete arrays previously
# created by deploy.rb. Given a set of template server arrays and ELBs in JSON
# input.

require 'rubygems'
require 'json'

$file_dir = File.expand_path(File.dirname(__FILE__))

require File.join($file_dir, 'defaults.rb')
require File.join($file_dir, 'get_logger.rb')
require File.join($file_dir, 'get_right_client.rb')
require File.join($file_dir, 'elb_manager.rb')
require File.join($file_dir, 'node_manager.rb')

# Global logger
$log = get_logger()

# Parse command line arguments.  Some defaults come from node_manager.rb
def parse_arguments()
  options = {
    :json => nil,
    :oauth2_api_url => $DEFAULT_OAUTH2_API_URL,
    :refresh_token => nil,
    :api_version => $DEFAULT_API_VERSION,
    :api_url => $DEFAULT_API_URL,
    :dryrun => nil,
    :env => $DEFAULT_ENV,
    :old_build_url => nil,
  }

  parser = OptionParser.new do|opts|
    opts.banner = "Usage: deploy.rb [options]"

    opts.on('-e', '--env ENV', 'Deployment environment string.') do |env|
      options[:env] = env;
    end

    opts.on('-o', '--old_build_url OLD_BUILD_URL',
            'Jenkins Build URL for the current install.') do |old_build_url|
      options[:old_build_url] = old_build_url;
    end

    opts.on('-d', '--dryrun', 'Dryrun. Do not make changes.') do
      options[:dryrun] = true
      $log.info('Dryrun is on.  Not making any changes')
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

  if options[:old_build_url].nil?
    abort('--old_build_url is required.')
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

# Main function.
#
def main()
  args = parse_arguments()
  right_client = get_right_client(args[:oauth2_api_url],
                                  args[:refresh_token],
                                  args[:api_version],
                                  args[:api_url])

  old_release_version = get_release_version(args[:old_build_url])
  old_short_version = get_short_version(old_release_version)

  config = parse_json_file(args[:json])

  #### Delete arrays

  all_arrays = find_server_arrays(right_client, old_short_version)

  # This issues an async task. We'll check the count later.
  for array in all_arrays
      if not args[:dryrun]
          $log.info('Terminating array %s' % array.name)
          array.multi_terminate(terminate_all=true)
      elsif
          $log.info('Would have terminated array %s' % array.name)
      end
  end

  # Wait for all arrays to be empty before deleting them.
  $log.info('Checking if arrays are empty...')
  while all_arrays.count > 0
    for array in all_arrays
        count = array.instances_count
        $log.info('Array %s has %s instances.')
        if count == 0
            if args[:dryrun]
                $log.info('Would have deleted the entire array...')
            else
                $log.info('Deleteing the entire array...')
                array.destroy
            end
        end
    end
    if not args[:dryrun]
        all_arrays = find_server_arrays(right_client, old_short_version)
    elsif
        all_arrays = []  # Faking for dry run
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
