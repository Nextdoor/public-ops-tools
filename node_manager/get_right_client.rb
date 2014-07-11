# Returns OAuth2 access token of RightScale.
#
# * *Args*    :
#   - +refresh_token+ -> string for RightScale refresh token for OAuth2
#   - +right_client+ -> instance of RestClient
#   - +api_version+ -> string for RightScale version
#
# * *Returns* :
#   - string for OAuth2 access token of RightScale
#
def get_access_token(right_client, refresh_token, api_version)
  post_data = Hash.new()
  post_data['grant_type'] = 'refresh_token'
  post_data['refresh_token'] = refresh_token

  right_client.post(post_data,
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


# Get an instance of the RightScale API client
#
# * *Args*    :
#   - +oauth2_api_url+ -> RightScale oauth API URL
#   - +refresh_token+ -> RightScale API token
#   - +api_version+ -> RightScale API version number
#   - +api_url+ -> RightScale API URL
#
def get_right_client(oauth2_api_url, refresh_token, api_version, api_url)
  # Fetch OAuth2 access token
  client = RestClient::Resource.new(oauth2_api_url,
                                    :timeout => $DEFAULT_OAUTH_TIMEOUT)
  access_token = get_access_token(client, refresh_token, api_version)

  # Check if any server array having the same name, if yes, exit.
  cookies = {}
  cookies[:rs_gbl] = access_token
  return RightApi::Client.new(:api_url => api_url,
                              :api_version => api_version,
                              :cookies => cookies)
end
