require 'rubygems'
require 'rspec/autorun'
require 'rspec/core'
require './node_manager'

RSpec.configure do |config|
  config.mock_with :rspec do |c|
    c.syntax = [:should, :expect]
  end
end

describe 'get_release_version' do
  it "parse the version" do
    expect(get_release_version(
        'http://jenkinshost.com/project_20140409-035643%7Erelease-0007a.bb93bbc.dsc')
    ).to eq('20140409-035643~release-0007a.bb93bbc')

    expect(get_release_version(
        'http://jenkinshost.com/project_20140409-035643%7Emaster.bb93bbc.dsc')
    ).to eq('20140409-035643~master.bb93bbc')
  end
end

describe 'get_queue_prefix' do
  it 'parse prefix' do
    expect(
        get_queue_prefix('20140409-035643~release-0007a.bb93bbc')
    ).to eq('0007a-bb93bbc')

    expect(
        get_queue_prefix('20140409-035643~release.bb93bbc')
    ).to eq('release-bb93bbc')

    expect(
        get_queue_prefix('20140409-035643~master.bb93bbc')
    ).to eq('master-bb93bbc')
  end
end

describe 'get_server_array_name' do
  it 'should compile server array names' do
    queue_prefix = get_server_array_name(
        'staging', 'uswest1', 'fe', '0008a')
    expect(queue_prefix).to eq('staging-fe-0008a-uswest1')

    queue_prefix = get_server_array_name(
        'staging', 'uswest1', 'nextdoor.com,taskworker', '0008a')
    expect(queue_prefix).to eq('staging-taskworker-0008a-uswest1')
  end
end

describe 'get_puppet_facts' do
  it 'should create proper puppet array' do
    facts = get_puppet_facts(
     'uswest1', 'nextdoor.com taskworker', 'prod', 'abcd')

    expect(facts).to eq(
        'array:["text:base_class=node_prod::nsp","text:shard=uswest1",'\
        '"text:nsp=nextdoor.com=abcd taskworker=abcd"]'
    )
  end
end

describe 'get_access_token' do
  class FakeResponse
    def to_str
      '{"access_token": "unit-test-value" }'
    end

    def code
      200
    end
  end
  class FakeClient
    def post(post_data, args, &callback)
      response = FakeResponse.new()
      callback.call(response, nil, nil)
    end
  end

  it 'should do token stuff' do
    fake_client = FakeClient.new()
    token = get_access_token(fake_client, 'unit', 'test')
    expect(token).to eq('unit-test-value')
  end
end
