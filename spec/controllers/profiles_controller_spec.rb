require File.dirname(__FILE__) + '/../spec_helper'

describe ProfilesController do

  before do 
    #mock_event_group
    #mock_viewer_as_projects_coordinator
    #mock_project
    #mock_profile
    #mock_login
    stub_viewer_as_event_group_coordinator
    stub_event_group
    stub_form
    stub_project
    stub_profile
    stub_appln
    setup_login

    @params = { :id => @profile.id }
  end
  
  it "should create new profile with new appln" do
    Appln.should_receive(:create).and_return(mock_model(Appln))
    Profile.should_receive(:create).and_return(@profile)
    @profile.stub!(:manual_update => true, :reload => true)
    post 'create', { :profile => { :appln_id => 'new', :viewer_id => 1 } }
    assigns[:profile].should_not be_nil
    response.should be_redirect
  end
  
  it "should update profile" do
      @profile.should_receive(:manual_update).with(nil, @viewer).and_return(@viewer)
      post 'update', @params
      flash[:notice].should eql("Successfully updated #{@viewer.name}'s profile.")
    end
    
    it "should make a new empty profile" do
      get 'new'
      assigns[:profile].should be_new_record
    end
    
    it "should render list" do
      post 'index'
      response.should redirect_to('http://test.host/profiles/list')
    end
    
    it "should set costing" do
      post 'costing', :id => @profile.id
      assigns[:submenu_title].should eql('costing')
    end
    
end
