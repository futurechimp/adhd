require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'couchrest'
require File.dirname(__FILE__) + '/../../lib/adhd/models/node_doc'

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

  end


end

