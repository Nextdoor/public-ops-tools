require 'rubygems'
require 'rspec/autorun'
require 'rspec/core'

require File.join(File.expand_path(File.dirname(__FILE__)), 'elb_manager.rb')

RSpec.configure do |config|
  config.mock_with :rspec do |c|
    c.syntax = [:expect]
  end
end

describe 'parse_arguments' do
    it "should require an action" do
      expect {
          elb_parse_arguments()
      }.to raise_error(/must specify an action/)
    end

    it "should work with all the needed arguments passed" do
        ARGV = ['--add',
                '--elb', 'unit-test',
                '--server_array','unit-test-array',
                '--refresh_token', '123unit']

        expect {
            elb_parse_arguments()
        }.to_not raise_error

    end
end
describe 'update_elb' do

    before :each do
      # Create a mocked object to track RightScale API calls
      @rs_mock = double('RightScale')
      allow(@rs_mock).to receive(:new) { @client }
      @sa_mock = double('ServerArray')
      stub(:find_server_array) { @sa_mock }
    end

    it "should raise exception with bad action" do
      expect {
        update_elb(false, @rs_mock, 'fake_elb', 'fake_sa', 'fake_url', 'bad')
      }.to raise_error(/Action must be/)
    end

    # Testing 'add' action
    it "update_elb() with dryryn       => false,
                          right_client => mock,
                          elb          => foo_elb,
                          server_array => foo_sa,
                          action       => add" do

      stub(:set_default_elb)

      @sa_mock.should_receive(:multi_run_executable).with(
        :right_script_href => '/api/right_scripts/438671001',
        :inputs => { 'ELB_NAME' => 'text:foo_elb' }) { @task_mock }

      update_elb(false, @rs_mock, 'foo_elb', 'foo_sa', 'staging', 'add')

    end

    # Testing 'remove' action
    it "update_elb() with dryrun       => false,
                          right_client => mock,
                          elb          => foo_elb,
                          server_array => foo_sa,
                          action       => remove" do

      stub(:set_default_elb)

      @sa_mock.should_receive(:multi_run_executable).with(
        :right_script_href => '/api/right_scripts/396277001',
        :inputs => { 'ELB_NAME' => 'text:foo_elb' } ) { @task_mock }

      update_elb(false, @rs_mock, 'foo_elb', 'foo_sa', 'staging', 'remove')
    end

end


describe 'wait_for_elb_tasks' do
  it "should abort if tasks don't complete fast enough." do

    stub(:check_elb_task).with('test') { false }  # Fail all tasks.
    #check_elb_task = double('check_elb_task')
    #allow(check_elb_task).to receive(:task).and_return(false)

    $RS_TIMEOUT = 0  # Don't retry

    expect {
      wait_for_elb_tasks(['test'])
    }.to raise_error(/Timeout waiting on RightScale task!/)

    #check_elb_task.should_receive('test')
  end

  it "should exit without a problem if tasks complete." do
    stub(:check_elb_task).with('test') { true }  # Pass all tasks.

    expect(wait_for_elb_tasks(['test'])).to eq(nil)
  end
end

describe "check_elb_task" do

  class FakeTask
    s = 1
  end

  it "should return true if a taks is completed" do
    task = double('task')
    summary = double('summary')
    allow(summary).to receive(:summary).and_return('abc completed abc')

    allow(task).to receive(:show).and_return(summary)

    expect(check_elb_task(task)).to eq(true)
  end

  it "should return false if a taks is incomplete" do
    task = double('task')
    summary = double('summary')
    allow(summary).to receive(:summary).and_return('abc abc')

    allow(task).to receive(:show).and_return(summary)

    expect(check_elb_task(task)).to eq(false)
  end

  it "should abort if a taks is failed" do
    task = double('task')
    summary = double('summary')
    allow(summary).to receive(:summary).and_return('abc failed abc')

    allow(task).to receive(:show).and_return(summary)

    expect {
        check_elb_task(task)
    }.to raise_error(/failed/)
  end
end
