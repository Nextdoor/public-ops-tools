require 'rubygems'
require 'rspec/autorun'
require 'rspec/core'
require './find_server_array'

RSpec.configure do |config|
  config.mock_with :rspec do |c|
    c.syntax = [:expect]
  end
end

describe 'find_server_array()' do

    class FakeSA
        def name
            'unit-test'
	end
    end

    class FakeFilter
	@@sa = FakeSA.new()

        def index
          return [@@sa]
        end
    end

    it 'should return one array' do
        rc = double('right_client')
	ff = FakeFilter.new()
	sa = ff.index[0]

        allow(rc).to receive(:server_arrays).and_return(ff)

        expect(find_server_array(rc, 'unit-test')).to eq(sa)
    end

    it 'should return nil for no arrays' do
        rc = double('right_client')
	ff = FakeFilter.new()
	sa = ff.index[0]

        allow(rc).to receive(:server_arrays).and_return(ff)

        expect(find_server_array(rc, 'bad-array-name')).to eq(nil)
    end
end

describe 'find_server_arrays()' do

    it 'should return Filter object' do
        class FakeFilter
            def index
              return 'unit-test'
            end
        end
        rc = double('right_client')
	allow(rc).to receive(:server_arrays).and_return(FakeFilter.new())

        expect(
	  find_server_arrays(rc, 'unit-test')).to eq('unit-test')
    end

end
