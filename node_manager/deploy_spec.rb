require 'rubygems'
require 'rspec/autorun'
require 'rspec/core'
require './deploy'

RSpec.configure do |config|
  config.mock_with :rspec do |c|
    c.syntax = [:expect]
  end
end

describe 'parse_arguments' do

    it 'should work' do
        ARGV = ['--json', 'test.json',
                '--refresh_token', 'unit-test',
                '--build_url', 'unit/test.com',
                '--old_build_version', '0001a-000000']
        parse_arguments()
    end

end
describe 'main()' do

    it 'should no-op with empty config' do

        stub(:find_server_arrays) { [] }
        stub(:parse_arguments) { {} }
        stub(:get_right_client) { }
        stub(:get_release_version) { 'unit-test-release-version' }
        stub(:get_short_version) { 'utrv' }

        stub(:parse_json_file) { {} }  # Empty config!

        expect { main() }.not_to raise_error
    end
end
