#! /usr/bin/env ruby

# This script uses node_manager and elb_manager to deploy full environments.
# Given a set of template server arrays and ELBs, we clone the server arrays
# to create new ones.  Then we add the new server arrays to the existing ELBs,
# and remove the old server arrays from the ELBs.  We perform these operations
# in threads, so we can run operations concurrently.

require 'rubygems'
require 'json'

require './get_right_client'
require './elb_manager'
require './node_manager'

# Parse command line arguments.  Some defaults come from node_manager.rb
def parse_arguments()
  options = {
    :json => nil,
    :oauth2_api_url => $DEFAULT_OAUTH2_API_URL,
    :refresh_token => nil,
    :api_version => $DEFAULT_API_VERSION,
    :api_url => $DEFAULT_API_URL,
  }

  parser = OptionParser.new do|opts|
    opts.banner = "Usage: deploy.rb [options]"

    opts.on('-j', '--json JSON',
            'JSON file containing server array and ELB IDs.') do |json|
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

  if not options[:json]
    abort('You must provide a JSON input file.')
  end

  if not options[:refresh_token]
    abort('You must specify a refresh token.')
  end

  return options
end

# Parse provided JSON file and return output
def parse_json(fname)
  file = open(fname)
  json = file.read
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
  json = parse_json(args[:json])

  json.each do |line|
    elb_name = line[0]
    tmpl_server_array = line[1]
    # clone arrays in threads, wait, etc
  end

  json.each do |line|
    elb_name = line[0]
    tmpl_server_array = line[1]
    # add/remove from/to ELBs in threads, wait, etc
  end
end

#
# Program entry.
#
if __FILE__ == $0
  main()
end
