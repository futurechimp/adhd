<<<<<<< HEAD:test/test_adhd.rb
require 'helper'

class TestAdhd < Test::Unit::TestCase
  should "probably rename this file and start testing for real" do
    flunk "hey buddy, you should probably rename this file and start testing for real"
  end
end
=======
require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'adhd'
require File.dirname(__FILE__) + '/../models'

class TestAdhd <  Test::Unit::TestCase

  context "An adhd node" do
    context "at startup" do

      setup do
        assert_nothing_raised do
          NODESERVER = CouchRest.new("http://192.168.1.104:5984")
          NODESERVER.default_database = "node_db"
          @node_db = CouchRest::Database.new(NODESERVER, "node_db")
        end
      end

      should_eventually "create a view for name" do
        # @node_db.get("_design/node")
      end

      context "if given another node url" do
        should_eventually "replicate the remote node database" do
        end
      end

      should_eventually "have a node descriptor in its database for itself" do
      end
    end
  end


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

  end

  private

end

>>>>>>> 15388c36a078b8eee9bc17c79501985e54be519b:test/test_adhd.rb
