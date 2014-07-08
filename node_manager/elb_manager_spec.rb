require 'elb_manager'

describe 'update_elb' do
  describe 'update_elb checks' do

#    before :each do
      # Create a mocked object to track RightScale API calls
#      @rs_mock = double('RightScale')
#      allow(@rs_mock).to receive(:new) { @client }
#    end

    it "should raise exception with bad action" do
      @rs_mock = double('RightScale')

      expect {
        update_elb(@rs_mock, 'fake_elb', 'fake_sa', 'fake_url', 'bad' )
      }.to raise_error(/Action must be/)
      end
    end

    it "elb => foo_elb, server_array => foo_sa, action => add" do
      rs_mock = double('RightScale')
      sa_mock = double('ServerArray')
      task_mock = double('TaskOutput')
      task_mock_summary = ('TaskOutputSummary')
      
      stub(:find_server_array) { sa_mock }

      task_mock.should_receive(:show) {
        task_mock_summary
      }
      task_mock_summary.should_receive(:summary) { 'Foo' }

      sa_mock.should_receive(:multi_run_executable).with(
        :right_script_href => 'fake_url',
        :inputs => { 'ELB_NAME' => 'text:foo_elb' } ) {
        task_mock
      }

      update_elb(rs_mock, 'foo_elb', 'foo_sa', 'fake_url', 'add')
  
  # @rs_mock.should_receive(:some_method).once.with(arg1,arg2).and_return('foo')
  end
end
