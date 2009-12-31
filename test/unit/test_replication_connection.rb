require 'rubygems'
require 'eventmachine'
require 'couchrest'

require 'test/unit'
require 'shoulda'
require File.dirname(__FILE__) + '/../../lib/adhd/replication/connection'
require File.dirname(__FILE__) + '/../../lib/adhd/replication/notifier'
require File.dirname(__FILE__) + '/../../lib/adhd/cluster/node'

class TestReplicationConnection <  Test::Unit::TestCase

  context "A couple of nodes" do
    setup do
      @node1 = Node.new
      @node1.name = "test1"
      @node1.url = "http://localhost:5984"
      @node1_db = @node1.get_node_db
      @node2 = Node.new
      @node2.name = "test2"
      @node2.url = "http://localhost:5984"
      @node2_db = @node2.get_node_db
    end

    teardown do
      @node1_db.delete!
      @node2_db.delete!
    end

    should "build a replication connection" do
      endconn = Proc.new do |ev, data|
        assert ev == :rec

        # Stop the event machine
        EM::stop_event_loop()
      end
      conn = Adhd::Replication::Connection.new @node1, @node1_db, @node2, @node2_db, endconn
      @node2_db.save_doc(@node2)
      @node2_db.save_doc(@node1)

      assert @node2_db.get(@node2["_id"])
      assert @node2_db.get(@node1["_id"])
      EM::run {
        conn.start
      }
      assert @node1_db.get(@node2["_id"])
      assert @node1_db.get(@node1["_id"])

   end

    should "throw an exception if the second does not exist" do
      endconn = Proc.new do |ev, data|
        assert ev == :rec

        # Stop the event machine
        EM::stop_event_loop()
      end

      nonexistent_node = Node.new
      nonexistent_node.name = "a_nonexistent_node"
      nonexistent_node.url = "http://some.nonexistent.node"
      nonexistent_node_db = nonexistent_node.get_node_db
      conn = Adhd::Replication::Connection.new @node1, @node1_db, nonexistent_node, nonexistent_node_db, endconn

      EM::run {
        begin
          conn.start
          assert false
          EM::stop_event_loop()
        rescue
          assert true
          EM::stop_event_loop()
        end
      }

    end

    should "throw an exception if the first does not exist" do
      endconn = Proc.new do |ev, data|
        assert ev == :rec

        # Stop the event machine
        EM::stop_event_loop()
      end

      nonexistent_node = Node.new
      nonexistent_node.name = "a_nonexistent_node"
      nonexistent_node.url = "http://some.nonexistent.node:9999"
      nonexistent_node_db = nonexistent_node.get_node_db
      conn = Adhd::Replication::Connection.new nonexistent_node, nonexistent_node_db, @node2, @node2_db, endconn

      EM::run {
        begin
          conn.start
          assert false
          EM::stop_event_loop()
        rescue
          assert true
          EM::stop_event_loop()
        end
      }
    end
  end

end

