require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'couchrest'
require File.dirname(__FILE__) + '/../../lib/adhd/models/node_doc'

# A db that always pretents to copy a db
module Fake_db 
  def get_target
    @target
  end
        
  def replicate_to t
    @target = t
  end

  def replicate_from target
    @target = t
  end
end

# A db that always throws a replication exception
module Blow_db
  def get_target
    @target
  end
        
  def replicate_to t
    throw Exception.new 
  end

  def replicate_from target
    @target = t
  end

end

class TestAdhd <  Test::Unit::TestCase

  context "The Node model" do
    setup do
      @node = Node.new
    end

    should "have a name property" do
      assert @node.respond_to? "name"
    end

    should "have a url property" do
      assert @node.respond_to? "url"
    end

    should "have have an is_store property" do
      assert @node.respond_to? "is_store"
    end

    should "have an is_management property" do
      assert @node.respond_to? "is_management"
    end

    should "have an is_directory property" do
      assert @node.respond_to? "is_directory"
    end

    should "have a status property" do
      assert @node.respond_to? "status"
    end

    should "have timestamp properties" do
      assert @node.respond_to? "created_at"
      assert @node.respond_to? "updated_at"
    end

    should "have methods to replicate to and from other DBs" do
      assert @node.respond_to? "replicate_to"
      assert @node.respond_to? "replicate_from"
    end


   context "replication" do
        
    setup do
      @other_node = Node.new  
      
      # Simulate a DB class
      local_db_klass = Class.new do
        include Fake_db
      end
      local_blow_db_klass = Class.new do
        include Blow_db
      end


      @node.name = "Node1"
      @other_node.name = "Node2"
      @local_db = local_db_klass.new
      @local_blow_db = local_blow_db_klass.new          
    end
                
    should "copy databases across" do
      @node.replicate_to(@local_db, @other_node, "TARGET")
      assert @local_db.get_target && @local_db.get_target == "TARGET"
    end
    
    should "not copy to same node" do    
      assert !@node.replicate_to(@local_db, @node, "TARGET")
      assert !@local_db.get_target # Has not copied anything indeed
    end
    
    should "not copy to same node" do    
      assert !@node.replicate_to(@local_db, @node, "TARGET")
      assert !@local_db.get_target # Has not copied anything indeed
    end
    
    should "not copy to unavailable nodes" do
      @other_node.status = "UNAVAILABLE"
      assert !@node.replicate_to(@local_db, @other_node, "TARGET")
      assert !@local_db.get_target # Has not copied anything indeed
    end

    should "tag unavailable nodes" do
      Fake_node = Class.new do
        attr_accessor :status, :saved, :name
        def initialize
          @name = "Node2"
        end
        def save
          @saved = true
        end        
      end
      fake_node = Fake_node.new
      
      assert !@node.replicate_to(@local_blow_db, fake_node, "TARGET")
      assert fake_node.status == "UNAVAILABLE"
      assert fake_node.saved
    end
   
   end  

  end


end

