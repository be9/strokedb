require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

def setup
  setup_default_store
  setup_index
  Object.send!(:remove_const, 'Foo') if defined?(Foo)
  Object.send!(:remove_const, 'Bar') if defined?(Bar)
  Object.send!(:remove_const, 'User') if defined?(User)
  Object.send!(:remove_const, 'Email') if defined?(Email)
end

describe "Document validation" do
  before :each do
    setup
  end

  it "should treat an empty document as valid" do
    Foo = Meta.new
    s = Foo.new

    s.should be_valid
    s.errors.should be_empty
  end

  it "should not treat a document with errors as valid" do
    s = erroneous_stuff

    s.should_not be_valid
    s.errors.count.should == 2
    %w(123 456).each do |msg|
      s.errors.messages.include?(msg).should be_true
    end
  end

  it "should raise InvalidDocumentError on a save! call" do
    lambda { erroneous_stuff.save! }.should raise_error(InvalidDocumentError)
  end

  it "should not raise InvalidDocumentError on a save!(false) call" do
    lambda { erroneous_stuff.save!(false) }.should_not raise_error(InvalidDocumentError)
  end

  def erroneous_stuff
    Meta.new do
      on_validation do |doc|
        doc.errors.add(:something, "123")
        doc.errors.add(:other,     "456")
      end
    end.new
  end
end

describe "validates_presence_of" do
  before :each do
    setup 
  end

  it "should tell valid if slot is there" do
    Foo = Meta.new { validates_presence_of :name, :on => :save }
    s = Foo.new({:name => "Rick Roll"})
    s.should be_valid
  end

  it "should tell invalid if slot is absent" do
    Foo = Meta.new { validates_presence_of :name, :on => :save }
    s = Foo.new

    s.should_not be_valid
    s.errors.messages.should == [ "Foo's name should be present on save" ]
  end
end

# we use validates_presence_of to test common validations behavior (:on, :message)

describe "Validation helpers" do
  before(:each) { setup }

  it "should respect :on => :create" do
    Foo = Meta.new { validates_presence_of :name, :on => :create }
    s1 = Foo.new
    bang { s1.save! }

    s2 = Foo.new(:name => "Rick Roll")
    no_bang { s2.save! }
    s2.remove_slot!(:name)
    no_bang { s2.save! }
  end

  it "should respect :on => :update" do
    Foo = Meta.new { validates_presence_of :name, :on => :update }
    
    s = Foo.new
    no_bang { s.save! }
    bang { s.save! }
    s[:name] = "Rick Roll"
    no_bang { s.save! }
  end

  it "should respect :on => :save" do
    Foo = Meta.new { validates_presence_of :name, :on => :save }
    s1 = Foo.new
    bang { s1.save! }

    s2 = Foo.new(:name => "Rick Roll")
    no_bang { s2.save! }
    s2.remove_slot!(:name)
    bang { s2.save! }
  end

  it "should respect :message" do
    Foo = Meta.new do 
      validates_presence_of :name, :on => :save, :message => 'On #{on} Meta #{meta} SlotName #{slotname}'
    end

    s = Foo.new
    s.valid?.should be_false
    s.errors.messages.should == [ "On save Meta Foo SlotName name" ]
  end

  it "should respect :if" do
    Foo = Meta.new do validates_presence_of :name, :on => :save, :if => proc { true } end
    bang { Foo.create! }
    Bar = Meta.new do validates_presence_of :name, :on => :save, :if => proc { false } end
    no_bang { Bar.create! }
  end
  
  it "should respect :unless" do
    Foo = Meta.new do validates_presence_of :name, :on => :save, :unless => proc { false } end
    bang { Foo.create! }
    Bar = Meta.new do validates_presence_of :name, :on => :save, :unless => proc { true } end
    no_bang { Bar.create! }
  end
  
  it "should respect both :if and :unless when given" do
    Foo = Meta.new do validates_presence_of :name, :on => :save, :if => proc { false }, :unless => proc { false } end
    no_bang { Foo.create! }
    Bar = Meta.new do validates_presence_of :name, :on => :save, :if => proc { true }, :unless => proc { false } end
    bang { Bar.create! }
  end
 
  it "should allow to use document slot for :if and :unless evaluation" do
    Foo = Meta.new do validates_presence_of :name, :on => :save, :if => :slot end
    bang { Foo.create!(:slot => true) }
    no_bang { Foo.create!(:slot => false) }
    
    Bar = Meta.new do validates_presence_of :name, :on => :save, :unless => :slot end
    no_bang { Bar.create!(:slot => true) }
    bang { Bar.create!(:slot => false) }
  end
  
  it "should allow to use a string for :if and :unless evaluation" do
    Foo = Meta.new do 
      validates_presence_of :name, :on => :save, :if => "!some_method"
      def some_method; self.some_slot end
    end
    
    no_bang { Foo.create!(:some_slot => true) }
    bang { Foo.create!(:some_slot => false) }
    
    Bar = Meta.new do 
      validates_presence_of :name, :on => :save, :unless => "!some_method"
      def some_method; self.some_slot end
    end
    
    bang { Bar.create!(:some_slot => true) }
    no_bang { Bar.create!(:some_slot => false) }
  end

  it "should raise an ArgumentError when given something not callable for :if and :unless" do
    lambda do
      Meta.new { validates_presence_of :name, :on => :save, :if => 123  }
    end.should raise_error(ArgumentError)

    lambda do
      Meta.new { validates_presence_of :name, :on => :save, :unless => 123  }
    end.should raise_error(ArgumentError)
  end

  def bang
    lambda { yield }.should raise_error(InvalidDocumentError)
  end

  def no_bang
    lambda { yield }.should_not raise_error(InvalidDocumentError)
  end
end

describe "validates_type_of" do
  before(:each) do
    setup

    Email = Meta.new
    User = Meta.new { validates_type_of :email, :as => :email }
  end

  it "should treat absent slot as valid" do
    User.new.should be_valid
  end

  it "should actually check the type" do
    e = Email.create!
    User.new(:email => e).should be_valid
  end

  it "should treat other types as invalid" do
    OmgEmail = Meta.new
    e = OmgEmail.create!

    User.new(:email => e).should_not be_valid
    User.new(:email => "name@server.com").should_not be_valid
    u = User.new(:email => nil)
    u.should_not be_valid
    u.errors.messages.should == [ "User's email should be of type Email" ]
  end
end

describe "validates_uniqueness" do
  before :each do
    setup
    User = Meta.new { validates_uniqueness_of :email }
  end

  it "should treat absent slot as valid" do
    u1 = User.create!
    User.new.should be_valid
  end

  it "should treat unique slot values as valid" do
    u1 = User.create!(:email => "name@server.com")
    u2 = User.new(:email => "othername@otherserver.com")
    u2.should be_valid
  end
  
  it "should treat duplicate slot values as invalid" do
    u1 = User.create!(:email => "name@server.com")
    u2 = User.new(:email => "name@server.com")
    u2.should_not be_valid
    u2.errors.messages.should == [ "A document with a email of name@server.com already exists" ]
  end

  it "should respect slot name" do
    u1 = User.create!(:email => "name@server.com")
    u2 = User.new(:otherfield => "name@server.com")
    u2.should be_valid
  end

  it "should allow to modify an existing document" do
    u = User.create!(:email => "name@server.com", :status => :newbie)
    u.status = :hacker
    u.should be_valid
    u.save!
    u.status = :hax0r
    u.should be_valid
    u.save!
    u.email = "hax0r@hax0r.com"
    u.should be_valid
    u.save!
    u.email = "name@server.com"
    u.status = :newbie_again
    u.should be_valid
    u.save!
    u.email = "hax0r@hax0r.com"
    u.should be_valid
  end
end

<<<<<<< HEAD:strokedb-ruby/spec/document/validations_spec.rb
=======
describe "validates_confirmation_of" do
  it "should be implemented"
end

describe "validates_acceptance_of" do
  it "should be implemented"
end

describe "validates_length_of" do
  it "should be implemented"
end

describe "validates_uniqueness_of" do
  it "should be implemented"
end

describe "validates_format_of" do
  it "should be implemented"
end

describe "validates_inclusion_of" do
  it "should be implemented"
end

describe "validates_exclusion_of" do
  it "should be implemented"
end

describe "validates_associated" do
  it "should be implemented"
end
>>>>>>> 1de7e2cb3aac267c0e571b31867e34eba9d7488f:strokedb-ruby/spec/document/validations_spec.rb

describe "validates_numericality_of" do
<<<<<<< HEAD:strokedb-ruby/spec/document/validations_spec.rb
  before(:each) do
    setup
    User = Meta.new { validates_numericality_of :cash }
  end

  it "should treat absent slot as valid" do
    User.new.should be_valid
  end

  it "should actually check for numeric types" do
    User.new(:cash => 100).should be_valid
    User.new(:cash => 100.2).should be_valid
  end

  it "should treat other types as invalid" do
    User.new(:cash => User.create!).should_not be_valid
    User.new(:cash => "not a number").should_not be_valid
    User.new(:cash => nil).should_not be_valid
  end
end

describe "validates_numericality_of :only_integer => true" do
  before(:each) do
    setup
    User = Meta.new { validates_numericality_of :age, :only_integer => true }
  end

  it "should treat absent slot as valid" do
    User.new.should be_valid
  end

  it "should actually check for Integer numbers" do
    User.new(:age => 100).should be_valid
  end

  it "should treat other types as invalid" do
    User.new(:age => 100.2).should_not be_valid
    User.new(:age => User.create!).should_not be_valid
    User.new(:age => "not a number").should_not be_valid
    User.new(:age => nil).should_not be_valid
  end
=======
  it "should be implemented"
end

describe "Complex validations" do
  it "should run all validations for the same slot"
  it "should run all validations from all metas"
  it "should somehow deal with the case when different metas contain same validations types for the same slot"
>>>>>>> 1de7e2cb3aac267c0e571b31867e34eba9d7488f:strokedb-ruby/spec/document/validations_spec.rb
end

describe "Meta with validation enabled" do
  before(:each) do
    setup
    User = Meta.new { validates_uniqueness_of :email }
  end
  
  it "should be able to find instances of all documents" do
    doc = User.create! :email => "yrashk@gmail.com"
    User.find.should == [doc]
  end
end
