require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe "Meta module", :shared => true do

  it "should be able to instantiate new Document which is also SomeName" do
    obj = SomeName.new
    obj.should be_a_kind_of(Document)
    obj.should be_a_kind_of(SomeName)
  end
  
  it "should be able to instantiate new Document and save it" do
    new_doc = mock("new doc")
    new_doc.should_receive(:save!)
    SomeName.should_receive(:new).and_return(new_doc)
    obj = SomeName.create!
  end
  
  it "should have corresponding document" do
    doc = SomeName.document
    doc.should_not be_nil
    doc.should be_a_kind_of(Meta)
  end

  it "should find document instead of creating it" do
    doc = SomeName.document
    10.times {|i| SomeName.document.uuid.should == doc.uuid }
  end

  it "should save new document version if it was updated" do
    doc = SomeName.document    
    version = doc.version.clone
    new_doc = nil
    2.times do |i|
      Object.send!(:remove_const,'SomeName') if defined?(SomeName)
      @meta = Meta.new(:name => "SomeName", :description => "Something")  
      new_doc = SomeName.document
    end
    new_doc.uuid.should == doc.uuid
    new_doc.previous_version.should_not be_nil
    new_doc.previous_version.should == version
    new_doc.version.should_not == new_doc.previous_version
    new_doc.description.should == "Something"
  end

  it "should search for specified UUID with meta reference merged in" do
    a = SomeName.create!
    SomeName.find(a.uuid).should == a
  end
  
  it "should search for specified slots with meta reference merged in" do
    a = SomeName.create!(:slot1 => 1, :slot2 => 2)
    b = SomeName.create!(:slot1 => 1, :slot2 => 2)
    c = SomeName.create!(:slot1 => 2, :slot2 => 2)

    SomeName.find(:slot1 => 1, :slot2 =>2).sort_by {|d| d.uuid}.should == [a,b].sort_by {|d| d.uuid}
  end

  it "should find first document for specified slots with meta reference merged in on #find_or_create" do
    a = SomeName.create!(:slot1 => 1, :slot2 => 2)
    b = SomeName.create!(:slot1 => 1, :slot2 => 2)
    c = SomeName.create!(:slot1 => 2, :slot2 => 2)

    search = SomeName.find_or_create(:slot1 => 1, :slot2 =>2)
    (search == a || search == b).should be_true
  end

  it "should create document for specified slots with meta reference merged in on #find_or_create if such document was not found" do
    a = SomeName.create!(:slot1 => 1, :slot2 => 2)
    b = SomeName.create!(:slot1 => 1, :slot2 => 2)
    c = SomeName.create!(:slot1 => 2, :slot2 => 2)
    
    search = SomeName.find_or_create(:slot1 => 3, :slot2 =>2)
    search.slot1.should == 3
    search.should_not be_new
  end
  
end

describe "Meta module with name" do
  
  before(:each) do
    setup_default_store
    setup_index

    Object.send!(:remove_const,'SomeName') if defined?(SomeName)
    @meta = Meta.new(:name => "SomeName")  
  end

  it_should_behave_like "Meta module"

end

describe "Meta module without name" do
    
  before(:each) do
    setup_default_store
    setup_index
    
    Object.send!(:remove_const,'SomeName') if defined?(SomeName)
    SomeName = Meta.new
  end
  
  it_should_behave_like "Meta module"
  
  it "should have name defined in the document" do
    SomeName.document.name.should == 'SomeName'
  end
  
end

describe "Meta module with on_initialization callback" do
  
  before(:each) do
    setup_default_store
    setup_index
    
    Object.send!(:remove_const,'SomeName') if defined?(SomeName)
    SomeName = Meta.new do
      on_initialization do |obj|
        Kernel.send!(:on_initialization_called,obj.new?)
      end
    end
  end
  
  it "should receive this callback on meta instantiation" do
    Kernel.should_receive(:on_initialization_called).with(true)
    doc = SomeName.new
  end
  
  it "should be a sole meta receiving this callback when adding metas dynamically" do
    Object.send!(:remove_const,'SomeOtherName') if defined?(SomeOtherName)
    SomeOtherName = Meta.new do
      on_initialization do |obj|
        Kernel.send!(:other_on_initialization_called,obj.new?)
      end
    end
    Kernel.should_receive(:other_on_initialization_called).with(true).once
    doc = SomeOtherName.new
    Kernel.should_receive(:on_initialization_called).with(true).once
    doc.metas << SomeName
  end
  
end


describe "Meta module with on_load callback" do
  
  before(:each) do
    setup_default_store
    setup_index
    
    Object.send!(:remove_const,'SomeName') if defined?(SomeName)
    SomeName = Meta.new do
      on_load do |obj|
        Kernel.send!(:on_load_called,obj.new?)
      end
    end
  end
  
  it "should not receive this callback on meta instantiation" do
    Kernel.should_not_receive(:on_load_called)
    doc = SomeName.new
  end

  it "should  receive this callback on document load" do
    doc = SomeName.create!
    Kernel.should_receive(:on_load_called).with(false)
    SomeName.find(doc.uuid)
  end
  
  
end

describe "Meta module with before_save callback" do
  
  before(:each) do
    setup_default_store
    setup_index
    
    Object.send!(:remove_const,'SomeName') if defined?(SomeName)
    SomeName = Meta.new do
      before_save do |obj|
        Kernel.send!(:before_save_called,obj.new?)
      end
    end
  end
  
  it "should initiate callback on Document#save! (before actually saving it)" do
    s = SomeName.new
    Kernel.should_receive(:before_save_called).with(true)
    s.save!
  end

end

describe "Meta module with after_save callback" do
  
  before(:each) do
    setup_default_store
    setup_index
    
    Object.send!(:remove_const,'SomeName') if defined?(SomeName)
    SomeName = Meta.new do
      after_save do |obj|
        Kernel.send!(:after_save_called,obj.new?)
      end
    end
  end
  
  it "should initiate callback on Document#save! (after actually saving it)" do
    s = SomeName.new
    Kernel.should_receive(:after_save_called).with(false)
    s.save!
  end

end


describe "Meta module with on_new_document callback" do
  
  before(:each) do
    setup_default_store
    setup_index
    
    Object.send!(:remove_const,'SomeName') if defined?(SomeName)
    SomeName = Meta.new do
      on_new_document do |obj|
        Kernel.send!(:on_new_document,obj.new?)
      end
    end
  end
  
  it "should initiate callback on Document#new" do
    Kernel.should_receive(:on_new_document).with(true)
    s = SomeName.new
  end

  it "should not initiate callback on loaded Document" do
    Kernel.should_receive(:on_new_document).with(true).once
    s = SomeName.new
    s.save!
    s.reload
  end

end

describe "Combined meta module" do
  
  before(:each) do
    setup_default_store
    setup_index
    
    Object.send!(:remove_const,'User') if defined?(User)
    Object.send!(:remove_const,'Buyer') if defined?(Buyer)
    Object.send!(:remove_const,'Seller') if defined?(Seller)
    
    User = Meta.new(:x => 1)
    Buyer = Meta.new(:x => 2)
    Seller = Meta.new(:y => 3)
  end

  it "should initialize Document with all metas" do
    d = (User+Buyer+Seller).new
    d[:meta].should == [User.document,Buyer.document,Seller.document]
  end

  it "should be able to find respective documents" do
    d0 = User.create!
    User.find.should == [d0]
    d1 = (User+Buyer).create!
    (User+Buyer).find.should == [d1]
    d2 = (User+Buyer+Seller).create!
    (User+Buyer+Seller).find.should == [d2]
  end
  
  it "should merge #document" do
    (User+Buyer+Seller).document.x.should == 2
    (User+Buyer+Seller).document.y.should == 3
  end
  
  it "should make merged #document immutable" do
    (User+Buyer+Seller).document.should be_a_kind_of(ImmutableDocument)
  end
  
end
