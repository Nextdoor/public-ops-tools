# Find server array with the given name
#
# * *Args*    :
#   - +right_client+ -> instance of RightClient
#   - +server_array_name+ -> string for server_array_name returned from
#                            get_server_array_name()
#
# * *Returns* :
#   - Resource object for server array
#
def find_server_array(right_client, server_array_name)
  $log.debug('Using "%s" to find "%s"' % [right_client, server_array_name])
  server_arrays = right_client.server_arrays(
                    :filter => ["name=="+server_array_name]).index
  if server_arrays.nil? or server_arrays.size() == 0
    $log.info("NOT FOUND. #{server_array_name} is not found.")
    return nil
  elsif server_arrays[0].name == server_array_name
    $log.info("FOUND. #{server_array_name} exists.")
    return server_arrays[0]
  end
  return nil
end

# Find server arrays with the given name
#
# Simply a wrapper around right_client.server_arrays without all of the checks
# above.  Returns multiple server arrays if the server_array_name filter
# matches.
#
# * *Args*    :
#   - +right_client+ -> instance of RightClient
#   - +server_array_name+ -> string for server_array_name returned from
#                            get_server_array_name()
#
# * *Returns* :
#   - Resource object for server array(s)
#
def find_server_arrays(right_client, server_array_name)
  return right_client.server_arrays(
           :filter => ["name=="+server_array_name]).index
end
