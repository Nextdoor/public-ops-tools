#! /usr/bin/env ruby

# This script uses node_manager and elb_manager to deploy full environments.
# Given a set of template server arrays and ELBs, we clone the server arrays
# to create new ones.  Then we add the new server arrays to the existing ELBs,
# and remove the old server arrays from the ELBs.  We perform these operations
# in threads, so we can run operations concurrently.

require 'rubygems'
require 'json'

require './elb_manager'
require './node_manager'

# Parse command line arguments.
def parse_arguments()
  options = {
    :json => nil,
  }

  parser = OptionParser.new do|opts|
    opts.banner = "Usage: deploy.rb [options]"

    opts.on('-j', '--json JSON',
            'JSON file containing server array and ELB IDs.') do |json|
      options[:json] = json
    end
  end

  parser.parse!

  if not options[:json]
    abort('You must provide a JSON input file.')
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
  right_client = get_right_client(args)
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
