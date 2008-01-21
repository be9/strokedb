require File.dirname(__FILE__) + '/spec_helper'

describe "Newly created Document" do
  
  before(:each) do
    @store = mock("Store")
    @document = StrokeDB::Document.new(@store)
    @store.should_receive(:exists?).with(@document.uuid).any_number_of_times.and_return(false)
  end
  
  it "should have UUID" do
    @document.uuid.should match(StrokeDB::UUID_RE)
  end
  
  it "should be new" do
    @document.should be_new
  end
  
  it "should have no version" do
    @document.version.should be_nil
  end
  
  it "should have no slotnames" do
    @document.slotnames.should be_empty
  end
  
end
  

describe "Newly created Document with slots supplied" do
  
  before(:each) do
    @store = mock("Store")
    @document = StrokeDB::Document.new(@store,:slot1 => "val1", :slot2 => "val2")
  end
  
  it "should have version" do
    @document.version.should_not be_nil
  end
  
  it "should have corresponding slotnames, including __version__ slotname" do
    @document.slotnames.to_set.should == ['__version__','slot1','slot2'].to_set
  end
  
end
  