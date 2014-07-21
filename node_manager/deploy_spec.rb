require 'rubygems'
require 'rspec/autorun'
require 'rspec/core'
require './deploy'

RSpec.configure do |config|
  config.mock_with :rspec do |c|
    c.syntax = [:expect]
  end
end
