#!/usr/bin/ruby

require 'rubygems'

require 'logger'
require 'optparse'
require 'pp'
require 'right_api_client'
require 'uri'

$log = Logger.new(STDOUT)
$log.level = Logger::INFO

# Retruns release version.
#
# * *Args*    :
#   - +build_url+ -> string for jenkins build url, e.g.,
#      http://jenkins_host/..._20140409-035643%7Erelease-0007a.bb93bbc.dsc
# * *Returns* :
#   - string for release version, e.g.,
#     20140409-035643~release-0007a.bb93bbc
def get_release_version(args)
  build_url = args[:build_url]
  uri = URI.parse(build_url)
  decoded_path = URI.unescape(uri.path)
  parts = File.basename(decoded_path).split('_')
  return parts[1].chomp(File.extname(parts[1]))
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
#   - +release_version+ -> string for the value returned by get_release_version
#
# * *Returns* :
#   - string for server array name, e.g., prod-taskworker-0007a-uswest2
#
def get_server_array_name(args)
  env = args[:env]
  region = args[:region]
  service = args[:service]
  release_version = args[:release_version]
  parts = release_version.split('~')[1].split('.')
  sha = parts[1]
  release_parts = parts[0].split('-')
  version = ''
  if release_parts.size() == 2
    version = release_parts[1]
  else
    version = sha
  end
  return env + '-taskworker-' + version + '-' + region
end

# Returns OAuth2 access token of RightScale.
#
# * *Args*    :
#   - +refresh_token+ -> string for RightScale refresh token for OAuth2
#   - +oauth2_api_url+ -> string for RightScale OAuth2 api url
#   - +api_version+ -> string for RightScale version
#
# * *Returns* :
#   - string for OAuth2 access token of RightScale
#
def get_access_token(args)
  refresh_token = args[:refresh_token]
  oauth2_api_url = args[:oauth2_api_url]
  api_version = args[:api_version]

  client = RestClient::Resource.new(oauth2_api_url,
                                    :timeout => 15)

  post_data = Hash.new()
  post_data['grant_type'] = 'refresh_token'
  post_data['refresh_token'] = refresh_token

  client.post(post_data,
              :X_API_VERSION => api_version,
              :content_type => 'application/x-www-form-urlencoded',
              :accept => '*/*') do |response, request, result|
    data = JSON.parse(response)
    case response.code
    when 200
      $log.info('SUCCESS. Got access token from RightScale.')
      return data['access_token']
    else
      abort('FAILED. Failed to get access token.')
    end
  end
end

# Creates a server array.
#
# There are actually three steps:
# 1. Clone from a server array template
# 2. Rename the newly created server array
# 3. Launch new instances
#
# * *Args*    :
#   - +access_token+ -> string for RightScale access token for OAuth2
#   - +api_url+ -> string for RightScale api url
#   - +api_version+ -> string for RightScale version
#   - +tmpl_server_array+ -> integer for the template server array id
#   - +server_array_name+ -> string for server_array_name returned from get_server_array_name()
#
# * *Returns* :
#   - a RightScale Resource instance representing the newly created server array
#
def create_server_array(args)
  access_token = args[:access_token]
  api_url = args[:api_url]
  api_version = args[:api_version]
  tmpl_server_array = args[:tmpl_server_array]
  server_array_name = args[:server_array_name]
  instances = args[:instances]
  release_version = args[:release_version]
  service = args[:service]

  # Clone a server array
  cookies = {}
  cookies[:rs_gbl] = access_token
  client = RightApi::Client.new(:api_url => api_url,
                                :api_version => api_version,
                                :cookies => cookies)
  new_server_array = client.server_arrays(:id => tmpl_server_array).show.clone

  # Rename the newly created server array
  params = { :server_array => {
      :name => server_array_name }}
  new_server_array.show.update(params)
  $log.info("SUCCESS. Created server array #{server_array_name}")
  new_server_array.show.next_instance.show.inputs.multi_update('inputs' => {
            'PUPPET_ADDITIONAL_FACTS' => "text:shard=uswest2 nsp=#{service} nsp_version=#{release_version}"})
  $log.info("Will install #{service}=#{release_version} for all instances.")

  # Launch new instances
  for i in 1..instances
    instance = new_server_array.launch
    if not instance.nil?
      $log.info("SUCCESS. Launched #{instance.show.name}.")
    else
      $log.error('FAILED. Failed to launch an instance.')
    end
  end
  return new_server_array
end

# Find server array with the given name
#
# * *Args*    :
#   - +access_token+ -> string for RightScale access token for OAuth2
#   - +api_url+ -> string for RightScale api url
#   - +api_version+ -> string for RightScale version
#   - +server_array_name+ -> string for server_array_name returned from get_server_array_name()
#
# * *Returns* :
#   - Resource object for server array
#
def find_server_array(args)
  access_token = args[:access_token]
  api_url = args[:api_url]
  api_version = args[:api_version]
  server_array_name = args[:server_array_name]

  cookies = {}
  cookies[:rs_gbl] = access_token
  client = RightApi::Client.new(:api_url => api_url,
                                :api_version => api_version,
                                :cookies => cookies)
  server_arrays = client.server_arrays(:filter => ["name=="+server_array_name]).index
  if server_arrays.nil? or server_arrays.size() == 0
    $log.info("NOT FOUND. #{server_array_name} is not found.")
    return nil
  else
    $log.info("FOUND. #{server_array_name} exists.")
    return server_arrays[0]
  end
end

# Parse command line arguments.
def parse_arguments()
  options = {
    :api_url => 'https://my.rightscale.com',
    :api_version => '1.5',
    :env => 'staging',
    :region => 'uswest2',
    :service => 'service',
    :refresh_token => '',
    :oauth2_api_url => 'https://my.rightscale.com/api/oauth2',
    :tmpl_server_array => 1000,
    :build_url => '',
    :delete => false,
    :instances => 3
  }

  parser = OptionParser.new do|opts|
    opts.banner = "Usage: node_manager.rb [options]"
    opts.on('-u', '--api_url API_URL', 'RightScale API URL.') do |api_url|
      options[:api_url] = api_url;
    end

    opts.on('-v', '--api_version API_VERSION', 'RightScale API Version.') do |api_version|
      options[:api_version] = api_version;
    end

    opts.on('-e', '--env ENV', 'Deployment environment.') do |env|
      options[:env] = env;
    end

    opts.on('-r', '--region REGION', 'AWS Region.') do |region|
      options[:region] = region;
    end

    opts.on('-s', '--service SERVICE', 'The service that runs in this server array.') do |service|
      options[:service] = service;
    end

    opts.on('-t', '--refresh_token TOKEN', 'The refresh token for RightScale OAuth2.') do |refresh_token|
      options[:refresh_token] = refresh_token;
    end

    opts.on('-o', '--oauth2_api_url URL', 'RightScale OAuth2 URL.') do |oauth2_api_url|
      options[:oauth2_api_url] = oauth2_api_url;
    end

    opts.on('-l', '--tmpl_server_array TMPL_SERVER_ARRAY', 'RightScale Server Array template.') do |tmpl_server_array|
      options[:tmpl_server_array] = tmpl_server_array;
    end

    opts.on('-b', '--build_url BUILD_URL', 'Jenkins Build URL for service package.') do |build_url|
      options[:build_url] = build_url;
    end

    opts.on('-d', '--delete BOOLEAN', 'Whether or not to delete this server array. Should be either "true" or "false".') do |delete|
      options[:delete] = (delete == 'true')
    end

    opts.on('-i', '--instances INTEGER', 'Number of instances to launch in this server array.') do |instances|
      options[:instances] = instances.to_i
    end
  end

  parser.parse!
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
#
def delete_server_array(args)
  access_token = args[:access_token]
  api_url = args[:api_url]
  api_version = args[:api_version]
  server_array_name = args[:server_array_name]
  server_array = args[:server_array]

  if server_array.instances_count > 0
    $log.info("#{server_array.name} has instances running. Terminating them first.")
    instances =server_array.show.current_instances.index
    for instance in instances
      $log.info("Terminating #{instance.name} ...")
      instance.show.terminate
    end
    count = server_array.instances_count
    while count > 0
      $log.info("#{count} instances of #{server_array.name} are still running ... wait for 1 min ...")
      sleep 60
      server_array = find_server_array(:access_token => access_token,
                                       :api_url => api_url,
                                       :api_version => api_version,
                                       :server_array_name => server_array_name)
      count = server_array.instances_count
    end
  end
  server_array.destroy
  $log.info("SUCCESS. Destroyed #{server_array.name} ...")
end

# Main function.
#
def main()

  # Parse command line arguments
  options = parse_arguments()

  # Get release version from build url
  release_version = get_release_version(:build_url => options[:build_url])

  # Construct server array name
  server_array_name = get_server_array_name(:release_version => release_version,
                                            :service => options[:service],
                                            :env => options[:env],
                                            :region => options[:region])

  # Fetch OAuth2 access token
  access_token = get_access_token(:oauth2_api_url => options[:oauth2_api_url],
                                  :refresh_token => options[:refresh_token],
                                  :api_version => options[:api_version])

  # Check if any server array having the same name, if yes, exit.
  server_array = find_server_array(:access_token => access_token,
                                   :api_url => options[:api_url],
                                   :api_version => options[:api_version],
                                   :server_array_name => server_array_name)
  if not server_array.nil?
    if not options[:delete]
      # In the case of creating a new server array.
      abort("Skip creating #{server_array_name}." +
            ' You can manually launch more nodes in that server array via RightScale Web UI.')
    else
      # In the case of deleting a server array.
      delete_server_array(:server_array => server_array,
                          :access_token => access_token,
                          :api_url => options[:api_url],
                          :api_version => options[:api_version],
                          :server_array_name => server_array_name)
      abort("Finish deleting #{server_array_name}.")
    end
  else
    if options[:delete]
      abort("Nothing to delete.")
    end
  end

  # Create a new server array
  server_array = create_server_array(:access_token => access_token,
                                     :api_url => options[:api_url],
                                     :api_version => options[:api_version],
                                     :instances => options[:instances],
                                     :tmpl_server_array => options[:tmpl_server_array],
                                     :service => options[:service],
                                     :server_array_name => server_array_name,
                                     :release_version => release_version)
  if server_array.nil?
    abort("FAILED.")
  end
end

#
# Program entry.
#
if __FILE__ == $0
  main()
end
