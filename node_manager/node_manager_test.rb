require 'test/unit'
require_relative 'node_manager'

class String
  def code
    return 200
  end
end

class FakeClient
  def post(post_data, args, &callback)
    response = '{"access_token": "abcdef" }'
    callback.call(response, nil, nil)
  end
end

class NodeManagerTest < Test::Unit::TestCase
  # def setup
  # end

  # def teardown
  # end

  def test_get_release_version
    release_version = get_release_version('http://jenkinshost.com/project_20140409-035643%7Erelease-0007a.bb93bbc.dsc')
    assert(release_version == '20140409-035643~release-0007a.bb93bbc')

    release_version = get_release_version('http://jenkinshost.com/project_20140409-035643%7Emaster.bb93bbc.dsc')
    assert(release_version == '20140409-035643~master.bb93bbc')
  end

  def test_get_queue_prefix
    queue_prefix = get_queue_prefix('20140409-035643~release-0007a.bb93bbc')
    assert(queue_prefix == '0007a-bb93bbc')

    queue_prefix = get_queue_prefix('20140409-035643~release.bb93bbc')
    assert(queue_prefix == 'release-bb93bbc')

    queue_prefix = get_queue_prefix('20140409-035643~master.bb93bbc')
    assert(queue_prefix == 'master-bb93bbc')
  end

#def get_server_array_name(env, region, service, queue_prefix)
  def test_get_server_array_name
    queue_prefix = get_server_array_name('staging', 'uswest1',
                                         'fe', '0008a')
    assert(queue_prefix == 'staging-fe-0008a-uswest1')

    queue_prefix = get_server_array_name('staging', 'uswest1',
                                         'nextdoor.com,taskworker',
                                         '0008a')
    assert(queue_prefix == 'staging-taskworker-0008a-uswest1')
  end

  def test_get_puppet_facts
    facts = get_puppet_facts('uswest1',
                             'nextdoor.com,taskworker',
                             'prod',
                             'abcd')
    assert(facts == 'array:["text:base_class=node_prod::nsp","text:shard=uswest1","text:nsp=nextdoor.com=abcd taskworker=abcd"]')

    facts = get_puppet_facts('uswest1',
                             'nextdoor.com,hello,taskworker',
                             'staging',
                             'abcd')
    assert(facts == 'array:["text:base_class=node_staging::nsp","text:shard=uswest1","text:nsp=nextdoor.com=abcd hello=abcd taskworker=abcd"]')

    facts = get_puppet_facts('uswest1',
                             'taskworker',
                             '',
                             'abcd')
    assert(facts == 'array:["text:base_class=node_::nsp","text:shard=uswest1","text:nsp=taskworker=abcd"]')
  end

  def test_get_access_token
    fake_client = FakeClient.new()
    token = get_access_token(fake_client, 'abc', '1.5')
    assert(token == 'abcdef')
  end

  def test_create_server_array
    # TODO (wenbin)
  end

  def test_find_server_array
    # TODO (wenbin)
  end

  def test_are_queues_empty
    # TODO (wenbin)
  end

  def test_parse_arguments
    # TODO (wenbin)
  end

  def test_delete_server_array
    # TODO (wenbin)
  end

  def test_main
    # TODO (wenbin)
  end
end

