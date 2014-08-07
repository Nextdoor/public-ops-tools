require 'rubygems'
require 'rspec/autorun'
require 'rspec/core'
require './node_manager'

RSpec.configure do |config|
  config.mock_with :rspec do |c|
    c.syntax = [:should, :expect]
  end
end

describe 'parse_arguments' do
    it "should require an token" do
      expect {
          node_parse_arguments()
      }.to raise_error(/refresh_token is required/)
    end

    it "should work with all the needed arguments passed" do
        ARGV = ['--refresh_token', '123unit',
                '--tmpl_server_array', '123array',
                '--build_url', 'host/url']

        expect {
            node_parse_arguments()
        }.to_not raise_error

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

describe 'get_short_version' do
  it 'parse prefix' do
    expect(
        get_short_version('20140409-035643~release-0007a.bb93bbc')
    ).to eq('0007a-bb93bbc')

    expect(
        get_short_version('20140409-035643~release.bb93bbc')
    ).to eq('release-bb93bbc')

    expect(
        get_short_version('20140409-035643~master.bb93bbc')
    ).to eq('master-bb93bbc')
  end
end

describe 'get_server_array_name' do
  it 'should compile server array names' do
    sa_name = get_server_array_name(
        'staging', 'uswest1', 'fe', '0008a')
    expect(sa_name).to eq('staging-fe-0008a-uswest1')

    sa_name = get_server_array_name(
        'staging', 'uswest1', 'taskworker', '0008a')
    expect(sa_name).to eq('staging-taskworker-0008a-uswest1')

    sa_name = get_server_array_name(
        'staging', 'uswest1', 'taskworker', '0008a', 'mwise')
    expect(sa_name).to eq('staging-taskworker-mwise-0008a-uswest1')
  end
end

describe 'get_puppet_facts' do
  class FakeInputs
    @@name = 'nd-puppet/config/facts'
    @@value = 'array:nsp=nextdoor.com=installed taskworker=installed,app_group=us1'

    def self.name
      @@name
    end

    def self.value
      @@value
    end
  end

  it 'should create proper puppet array' do
    facts = get_puppet_facts([FakeInputs], 'uswest1', 'prod', 'abcd')

    expect(facts).to eq(
        'array:["text:nsp=nextdoor.com=abcd taskworker=abcd","text:app_group=us1"]')
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

describe 'clone_server_array' do

    it 'should work' do
        rc = double('right_client')
        sa = double('server_array')
        inp = double('inputs')
        allow(rc).to receive(:server_arrays).and_return(sa)
        allow(sa).to receive(:show).and_return(sa)
        allow(sa).to receive(:clone).and_return(sa)
        allow(sa).to receive(:next_instance).and_return(sa)
        allow(sa).to receive(:inputs).and_return(inp)
            allow(inp).to receive(:multi_update)
            allow(inp).to receive(:index)
        allow(sa).to receive(:elasticity_params).and_return(
            {'bounds'=> {'min_count' => 1}})
        allow(sa).to receive(:update)
        allow(sa).to receive(:launch)
        allow(sa).to receive(:index)

        stub(:get_puppet_facts) { {} }

        sa.should_receive(:launch).once
        clone_server_array(false, rc, '12345678', 'unit-test', 'release~123', 'frontend', 'staging', 'uswest0')
        $log.info('Checking that %s launched' % sa)
    end
end

describe 'min_instances_operational?' do

    it 'should work' do
        sa = double('server_array')
        server = double('server')

        allow(sa).to receive(:elasticity_params).and_return({'bounds' => {'min_count' => 2}})
        allow(sa).to receive(:current_instances).and_return(sa)
        allow(sa).to receive(:index).and_return([server, server])

        allow(server).to receive(:state).and_return('operational')

        expect(min_instances_operational?(sa)).to eq(true)
    end
end
