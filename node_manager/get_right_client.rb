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
  access_token = get_access_token(:client => client,
                                  :refresh_token => refresh_token,
                                  :api_version => api_version)

  # Check if any server array having the same name, if yes, exit.
  cookies = {}
  cookies[:rs_gbl] = access_token
  return RightApi::Client.new(:api_url => api_url,
                              :api_version => api_version,
                              :cookies => cookies)
end
