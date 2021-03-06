require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'couchrest'
require File.dirname(__FILE__) + '/../../lib/adhd/cluster/node'
require 'eventmachine'

# A db that always pretends to copy a db
#
module FakeDb
  def get_target
    @target
  end

  def replicate_to t
    @target = t
  end

  def replicate_from t
    @target = t
  end
end

# A db that always throws a replication exception
#
module BlowDb
  def get_target
    @target
  end

  def replicate_to t
    throw Exception.new
  end

  def replicate_from t
    throw Exception.new
  end

end

class TestNode <  Test::Unit::TestCase

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
          include FakeDb
        end
        local_blow_db_klass = Class.new do
          include BlowDb
        end

        @node.name = "Node1"
        @other_node.name = "Node2"
        @local_db = local_db_klass.new
        @local_blow_db = local_blow_db_klass.new
      end

      should "copy databases across" do
        @node.replicate_to("TARGET", @other_node, @local_db)
        assert @local_db.get_target && @local_db.get_target == "TARGET"
      end

      should "not copy to same node" do
        assert !@node.replicate_to("TARGET", @node, @local_db)
        assert !@local_db.get_target # Has not copied anything indeed
      end

      should "not copy to unavailable nodes" do
        @other_node.status = "UNAVAILABLE"
        assert !@node.replicate_to("TARGET", @other_node, @local_db)
        assert !@local_db.get_target # Has not copied anything indeed
      end

      should "tag unavailable nodes" do
        fake_node_klass = Class.new do
          attr_accessor :status, :saved, :name
          def initialize
            @name = "Node2"
          end
          def save
            @saved = true
          end
        end
        fake_node = fake_node_klass.new

        assert !@node.replicate_to("TARGET", fake_node, @local_blow_db)
        assert fake_node.status == "UNAVAILABLE"
        assert fake_node.saved
      end
    end
  end
end

