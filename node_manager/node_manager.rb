# !/usr/bin/env ruby

#
# Command to clone or delete server arrays.
#
# Clone server array: require --build_url
# - Rundeck job fetches recent build urls
#
# Delete server array: require --release_number
# - Be able to delete a specific release version
#
# The only two dependencies of this command are:
# 1. right_api_client
# 2. right_aws
#

require 'rubygems'
require 'optparse'
require 'pp'
require 'uri'

require './defaults'
require './find_server_array'
require './get_logger'
require './get_right_client'

# Global logger
$log = get_logger()

# Returns release version.
#
# * *Args*    :
#   - +build_url+ -> string for jenkins build url, e.g.,
#      http://jenkins_host/..._20140409-035643%7Erelease-0007a.bb93bbc.dsc
# * *Returns* :
#   - string for release version, e.g.,
#     20140409-035643~release-0007a.bb93bbc
def get_release_version(build_url)
  uri = URI.parse(build_url)
  decoded_path = URI.unescape(uri.path)
  parts = File.basename(decoded_path).split('_')
  release_version = parts[1].chomp(File.extname(parts[1]))
  if /\d{8}-\d{6}~.+\.\w{7}/.match(release_version)
    return release_version
  else
    $log.error('Malformed release version.
A good release version looks like this:
20140409-035643~release-0007a.bb93bbc')
    abort('Exit due to malformed release version.')
  end
end

# Returns queue prefix.
#
# If it's a release branch, then returns the release number;
# otherwise, returns the commit sha.
#
# * *Args*    :
#   - +release_version+ -> string for release version, e.g.,
#      20140409-035643~release-0007a.bb93bbc
#
# * *Returns* :
#      String for queue prefix
#
def get_queue_prefix(release_version)
  parts = release_version.split('~')[1].split('.')
  sha = parts[1]
  release_parts = parts[0].split('-')
  if release_parts.size() == 2
    return release_parts[1] + '-' + sha
  else
    return parts[0] + '-' + sha
  end
end

# Constructs server array name.
#
# If release_version contains release branch name "release-????", then use
# the release number; otherwise use commit SHA in release_version.
#
# * *Args*    :
#   - +env+ -> string for deployment environment, should be one of
#      "prod", "staging", and "dev"
#   - +region+ -> string for AWS regions, e.g., uswest2
#   - +service+ -> name of the service running on this array
#   - +release_version+ -> string for the value returned by get_release_version
#
# * *Returns* :
#   - string for server array name, e.g., prod-taskworker-0007a-uswest2
#
def get_server_array_name(env, region, service, queue_prefix)
  return "#{env}-#{service}-#{queue_prefix}-#{region}"
end

# Constructs puppet facts string for server array input.
#
# * *Args*    :
#   - +old_inputs+ -> Array of all RS inputs from the template used to append
#        release version to NSP facts
#   - +region+ -> string for AWS regions, e.g., uswest2
#   - +env+ -> string for deployment environment, should be one of
#      "prod", "staging", and "dev"
#   - +release_version+ -> string for the value returned by get_release_version
#
# * *Returns* :
#   - string for puppet facts
#
def get_puppet_facts(old_inputs, region, env, release_version)
  for input in old_inputs
    if input.name == 'nd-puppet/config/facts'
      old_facts = input.value
    end
  end

  # Example of old_facts before a split:
  #   array:nsp=nextdoor.com api,app_group=staging-us1
  # We also support replacing 'installed' with a version #, so this is valid
  #   array:nsp=nextdoor.com=installed api=installed,app_group=staging-us1
  old_facts = old_facts.split(':')[1]
  new_facts = []
  for fact in old_facts.split(',')
    if fact.start_with? 'nsp='
      fact = fact.gsub('installed', release_version)
    end
    new_facts.push(fact)
  end

  puppet_facts = "array:[\"text:"
  puppet_facts = puppet_facts + new_facts.join(', ')
  puppet_facts = puppet_facts + "\"]"
  return puppet_facts
end

# Clones a server array.
#
# There are actually three steps:
# 1. Clone from a server array template
# 2. Rename the newly created server array
# 3. Launch new instances
#
# * *Args*    :
#   - +dryrun+ -> boolean for whether or not to dry run
#   - +env+ -> string for deployment environment, should be one of
#      "prod", "staging", and "dev"
#   - +right_client+ -> instance for RightClient
#   - +tmpl_server_array+ -> integer for the template server array id
#   - +server_array_name+ -> string for server_array_name returned from
#                            get_server_array_name()
#   - +instances+ -> integer for number of instances to create inside this
#                    server array
#   - +release_version+ -> string for release version returned by
#                          get_release_version()
#   - +region+ -> string for aws region
#
# * *Returns* :
#   - a RightScale Resource instance representing the newly created server array
#
def clone_server_array(dryrun, right_client, tmpl_server_array,
                       server_array_name, instances,
                       release_version, service, env, region)

  # Clone a server array
  if dryrun
    $log.info("SUCCESS. Created server array #{server_array_name}")
    $log.info("Will launch #{instances} instances.")
    return
  end

  new_server_array = right_client.server_arrays(
                       :id => tmpl_server_array).show.clone

  # Rename the newly created server array
  params = { :server_array => {
      :name => server_array_name,
      :state => 'enabled'
  }}

  new_server_array.show.update(params)

  # Repeated calls with the same server_array_name can lead to failures
  # since RightScale uses the old name with 'v1' appended.  This sleeping
  # gives the rename time to complete.
  sleep 5

  $log.info("SUCCESS. Created server array #{server_array_name}")

  puppet_facts = get_puppet_facts(
                   new_server_array.show.next_instance.show.inputs.index,
                   region, env, release_version)
  new_server_array.show.next_instance.show.inputs.multi_update('inputs' => {
    'nd-puppet/config/facts' => puppet_facts})
  $log.info("Updated puppet input #{puppet_facts}.")

  # Launch new instances
  for i in 1..instances
    instance = new_server_array.launch
    if not instance.nil?
      $log.info("SUCCESS. Launched #{instance.show.name}.")
    else
      $log.error('FAILED. Failed to launch an instance.')
    end
  end

  new_server_array = nil
  while not new_server_array
    new_server_array = find_server_array(right_client, server_array_name)
  end

  return new_server_array
end

# Are all the instances running?
#
# Count the sum of all operational instances in this server array and check if
# there is enough of them to consider this array operational.
#
# * *Args*:
#   - +server_array+ -> array object
#   - +min_operational_instances+ -> number of expected instances to be considered 'operational'
#
# * *Returns*:
#   - +boolean+ -> 
#
def check_for_running_instances(server_array, min_operational_instances)
  # Wait min_instances to become operational.
  operational_instances = 0

  for instance in server_array.current_instances.index
    if instance.state == 'operational'
      operational_instances += 1
    end
  end

  if operational_instances >= min_operational_instances
    return true
  else
    return false
  end
end


# Are all SQS queues empty?
#
# * *Args*    :
#   - +aws_access_key_id+ -> string for aws_access_key
#   - +aws_secret_access_key+ -> string for aws_secret_access_key
#   - +region+ -> string for aws region for sqs
#
# * *Returns* :
#   - true if all queues are empty; otherwise, false
#
def are_queues_empty(aws_access_key_id, aws_secret_access_key, env, region,
                     queue_prefix)

  prefix = env + '-' + queue_prefix

  region_to_server_map = {
    'uswest1' => 'sqs.us-west-1.amazonaws.com',
    'uswest2' => 'sqs.us-west-2.amazonaws.com',
    'useast1' => 'sqs.us-east-1.amazonaws.com',
    'useast2' => 'sqs.us-east-2.amazonaws.com'
  }

  server = region_to_server_map[region]
  sqs = RightAws::SqsGen2.new(aws_access_key_id, aws_secret_access_key,
                              {:server => server })
  queues = sqs.queues(prefix)
  queues.each { |queue|
    queue_depth = queue.size
    $log.info(queue.name + ' queue depth: ' + queue_depth.to_s)
    if queue_depth > 0
      $log.error('Queue not empty.')
      return false
    end
  }
  $log.info("All queues with prefix \"#{prefix}\" are empty.")
  return true
end

# Parse command line arguments.
def parse_arguments()
  options = {
    :api_url => $DEFAULT_API_URL,
    :api_version => $DEFAULT_API_VERSION,
    :env => $DEFAULT_ENV,
    :region => $DEFAULT_REGION,
    :service => $DEFAULT_SERVICE_NAME,
    :refresh_token => nil,
    :oauth2_api_url => $DEFAULT_OAUTH2_API_URL,
    :tmpl_server_array => nil,
    :build_url => nil,
    :release_number => nil,
    :delete => false,
    :aws_access_key_id => nil,
    :aws_secret_access_key => nil,
    :instances => $DEFAULT_NUM_INSTANCES,
    :dryrun => false
  }

  parser = OptionParser.new do|opts|
    opts.banner = "Usage: node_manager.rb [options]"

    opts.on('-y', '--dryrun false', 'To dryrun?') do |dryrun|
      if dryrun == 'true'
        options[:dryrun] = true
      else
        options[:dryrun] = false
      end
    end

    opts.on('-u', '--api_url API_URL', 'RightScale API URL.') do |api_url|
      options[:api_url] = api_url;
    end

    opts.on('-v', '--api_version API_VERSION',
            'RightScale API Version.') do |api_version|
      options[:api_version] = api_version;
    end

    opts.on('-e', '--env ENV', 'Deployment environment.') do |env|
      options[:env] = env;
    end

    # TODO FIXME XXX use the build URL instead of the CLI arg
    opts.on('-n', '--release_number NUM',
            'Release number. E.g., if release_0007a, then release_number=0007a.'
            ) do |release_number|
      options[:release_number] = release_number.strip;
    end

    opts.on('-r', '--region REGION', 'AWS Region.') do |region|
      options[:region] = region;
    end

    opts.on('-s', '--service SERVICE',
            'Name of the service that runs in this server array.') do |service|
      options[:service] = service;
    end

    opts.on('-t', '--refresh_token TOKEN',
            'The refresh token for RightScale OAuth2.') do |refresh_token|
      options[:refresh_token] = refresh_token;
    end

    opts.on('-o', '--oauth2_api_url URL',
            'RightScale OAuth2 URL.') do |oauth2_api_url|
      options[:oauth2_api_url] = oauth2_api_url;
    end

    opts.on('-l', '--tmpl_server_array TMPL_SERVER_ARRAY',
            'Integer ID for RightScale Server Array template.') do |tmpl_server_array|
      options[:tmpl_server_array] = tmpl_server_array;
    end

    opts.on('-b', '--build_url BUILD_URL',
            'Jenkins Build URL for service package.') do |build_url|
      options[:build_url] = build_url;
    end

    opts.on('-a', '--aws_access_key_id ACCESS_KEY',
            'AWS_ACCESS_KEY_ID.') do |aws_access_key_id|
      options[:aws_access_key_id] = aws_access_key_id;
    end

    opts.on('-k', '--aws_secret_access_key SECRET_KEY',
            'AWS_SECRET_KEY_ID.') do |aws_secret_access_key|
      options[:aws_secret_access_key] = aws_secret_access_key;
    end

    opts.on('-d', '--delete BOOLEAN', 'Whether or not to delete this server array. Should be either "true" or "false".') do |delete|
      options[:delete] = (delete == 'true')
    end

    opts.on('-i', '--instances INTEGER', 'Number of instances to launch in this server array.') do |instances|
      options[:instances] = instances.to_i
    end

    opts.on('-t', '--taskworker BOOLEAN', 'Is this a taskworker array?  If so, we check the queue before deleting.') do |taskworker|
      options[:taskworker] = (taskworker == 'true')
    end
  end

  parser.parse!

  if options[:refresh_token].nil?
    abort('--refresh_token is required.')
  end

  if options[:env] != 'staging' and options[:env] != 'prod'
    abort('env must be staging or prod.')
  end

  if options[:delete]
    if options[:taskworker]
      if options[:aws_access_key_id].nil?
        abort('--aws_access_key_id is required.')
      end
      if options[:aws_secret_access_key].nil?
        abort('--aws_secret_access_key is required.')
      end
    end
    if options[:release_number].nil?
      abort('--release_number is required.')
    end
  else
    if options[:tmpl_server_array].nil?
      abort('--tmpl_server_array is required, which is the id of the template server array.')
    end
    if options[:build_url].nil?
      abort('--build_url is required.')
    end
  end

  return options
end

# Delete entire server array
#
# Need to terminate all instances in the server array first.
# Wait until all instances are gone, which will take minutes.
# Destroy the entire server array.
#
# * *Args*    :
#   - +server_array+ -> resource object for server array
#   - +server_array_name+ -> string for server array name
#   - +dryrun+ -> boolean for whether or not to dry run
#   - +right_client+ -> instance for RightClient
#
def delete_server_array(dryrun, right_client, server_array_name, server_array)
  # Disable auto-scaling first
  if not dryrun
      params = { :server_array => {
          :state => 'disabled'
        }}
      server_array.show.update(params)
  end

  if server_array.instances_count > 0
    $log.info("#{server_array.name} has instances running. Terminating them first.")
    instances = server_array.show.current_instances.index
    for instance in instances
      $log.info("Terminating #{instance.name} ...")
      if not dryrun
        begin
          instance.show.terminate
        rescue Exception => msg
          $log.info("Failed to terminate #{instance.name}: #{msg} ...")
        end
      end
    end

    count = server_array.instances_count
    if dryrun
      count = 0
    end

    while count > 0
      $log.info("#{count} instances of #{server_array.name} are still running ... wait for 1 min ...")
      sleep 60
      server_array = find_server_array(right_client, server_array_name)
      count = server_array.instances_count
    end
  end

  if not dryrun
    server_array.destroy
  end
  $log.info("SUCCESS. Destroyed #{server_array.name} ...")
end

# Main function.
#
def main()
  # Parse command line arguments
  args = parse_arguments()

  if args[:dryrun]
    $log.info('Dryrun mode. Should be safe to run!')
  end

  queue_prefix = args[:release_number]
  if not args[:delete]
    # Get release version from build url
    release_version = get_release_version(args[:build_url])
    queue_prefix = get_queue_prefix(release_version)
  end

  # Construct server array name
  server_array_name = get_server_array_name(args[:env], args[:region],
                                            args[:service], queue_prefix)

  if args[:delete] and args[:taskworker]
    queues_empty = are_queues_empty(args[:aws_access_key_id],
                                    args[:aws_secret_access_key],
                                    args[:env], args[:region], queue_prefix)

    if not queues_empty
      abort("Cannot destroy #{server_array_name} unless all queues with prefix \"#{queue_prefix}\" are empty.")
    end
  end

  # Instantiate the RightScale API
  right_client = get_right_client(args[:oauth2_api_url],
                                  args[:refresh_token],
                                  args[:api_version],
                                  args[:api_url])

  server_array = find_server_array(right_client, server_array_name)

  if not server_array.nil?
    if not args[:delete]
      # In the case of creating a new server array.
      abort("Skip creating #{server_array_name}." +
            ' You can manually launch more nodes in that server array via RightScale Web UI.')
    else
      # In the case of deleting a server array.
      delete_server_array(args[:dryrun], right_client, server_array_name,
                          server_array)
      $log.info("Finish deleting #{server_array_name}.")
      return
    end
  else
    if args[:delete]
      $log.info("Nothing to delete.")
      return
    end
  end

  # Clone a new server array
  server_array = clone_server_array(args[:dryrun], right_client,
                                    args[:tmpl_server_array], server_array_name,
                                    args[:instances], release_version,
                                    args[:service], args[:env], args[:region])

  while not check_for_running_instances(server_array, 1)
    $log.info("Waiting for at least one instance to boot...")
    sleep 60
  end

  if not args[:dryrun] and server_array.nil?
    abort("FAILED.")
  end
end

#
# Program entry.
#
if __FILE__ == $0
  main()
end
