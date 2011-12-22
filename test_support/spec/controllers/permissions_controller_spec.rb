require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')


# See cucumber tests (ie. /features/edit_document.feature) for more tests, including ones that test the edit method & view
# You can run the cucumber tests with 
#
# cucumber --tags @edit
# or
# rake cucumber

describe PermissionsController do
  describe "create" do
    it "should create a new permissions entry" do
      stub_solrizer = stub("solrizer", :solrize)
      Solrizer::Fedora::Solrizer.stubs(:new).returns(stub_solrizer)
      mock_ds = mock("Datastream")
      Hydra::RightsMetadata.stubs(:from_xml)
      Hydra::RightsMetadata.stubs(:new).returns(mock_ds)
      mock_ds.expects(:permissions).with({"person" => "_person_id_"}, "read")
      mock_ds.stubs(:content)
      mock_ds.stubs(:pid=)
      mock_ds.stubs(:dsid=)
      mock_ds.stubs(:save)
      mock_ds.stubs(:serialize!)
      mock_object = mock("object")
      mock_object.stubs(:datastreams).returns({"rightsMetadata"=>mock_ds})
      mock_inner = mock('Mock Inner')
      mock_object.stubs(:inner_object).returns(mock_inner)
      
      ActiveFedora::Base.expects(:load_instance).with("_pid_").returns(mock_object)

      post :create, :asset_id=>"_pid_", :permission => {"actor_id"=>"_person_id_","actor_type"=>"person","access_level"=>"read"}      
    end
  end
  describe "update" do
    it "should call Hydra::RightsMetadata properties setter" do
      stub_solrizer = stub("solrizer", :solrize)
      Solrizer::Fedora::Solrizer.stubs(:new).returns(stub_solrizer)
      mock_ds = mock("Datastream")
      Hydra::RightsMetadata.stubs(:from_xml)
      Hydra::RightsMetadata.stubs(:new).returns(mock_ds)
      mock_ds.expects(:update_permissions).with({"group" => {"_group_id_"=>"discover"}})
      mock_ds.stubs(:content)
      mock_ds.stubs(:pid=)
      mock_ds.stubs(:dsid=)
      mock_ds.stubs(:serialize!)
      mock_ds.stubs(:save)
      mock_object = mock("object")
      mock_object.stubs(:datastreams).returns({"rightsMetadata"=>mock_ds})
      mock_inner = mock('Mock Inner')
      mock_object.stubs(:inner_object).returns(mock_inner)
      
      ActiveFedora::Base.expects(:load_instance).with("_pid_").returns(mock_object)
      # must define new routes that can handle url like this
      # /assets/_pid_/permissions/group/_group_id_
      # /assets/:asset_id/permissions/:actor_type/:actor_id
      
      # this is what currently works 
      # post :update, :asset_id=>"_pid_", :actor_type=>"group", :actor_id=>"_group_id_", :permission => {"group"=>"_group_id_","level"=>"discover"}
      
      post :update, :asset_id=>"_pid_", :permission => {"group"=>{"_group_id_"=>"discover"}}
    end
  end
end