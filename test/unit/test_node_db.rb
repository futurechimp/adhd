require 'rubygems'
require 'test/unit'
require 'shoulda'
require File.dirname(__FILE__) + '/../../lib/adhd/models/node_db'

class Node
  def initialize event_list
    @event_list = event_list
  end
  
  attr_accessor :status, :name, :is_management

  def self.set_nodes node_list
    @@nodes = node_list
  end

  def self.by_is_management
    # Return a random set of nodes
    @@nodes.select {|n| n.is_management && n.is_management > 0}
  end

  def get_node_db
    @name
  end
  
  def replicate_to(local_db, other_node, remote_db)
    false if other_node.status == "UNAVAILABLE" or other_node.name == name
    @event_list << [:rep, local_db, remote_db]
    true
  end
  
  def replicate_from(local_db, other_node, remote_db)
    false if other_node.status == "UNAVAILABLE" or other_node.name == name
    @event_list << [:rep, remote_db, local_db]
    true
  end
  
end

class TestNodeDb <  Test::Unit::TestCase

  def get_random_node
    random_log = @node_log.sort_by { rand }      
    target_node = random_log[0]
   
    while  target_node.status == "UNAVAILABLE"
      random_log = random_log.sort_by { rand }      
      target_node = random_log[0]
    end
    target_node
  end


  context "A node database" do
    setup do
      # Make a CouchDB node_db and map the Node object there
      @event_log = []
      @node_log = []
      100.times do |i|        
        n = Node.new @event_log
        if i < 5
          n.is_management = 3
        end
        n.name = i
        if rand < 0.1
          n.status = "UNAVAILABLE"
        else
          n.status = "RUNNING"
        end
        @node_log << n  
      end
      
      Node.set_nodes @node_log
      
    end
    
    should "return some management nodes (even when fake)" do
      assert Node.by_is_management.length > 0
    end
    
    should "sync to a management node (PROBABILISTIC)" do
      old_log = @node_log.clone
      target_node = nil
      while !target_node or target_node.is_management
        target_node = get_random_node
      end
      ndb = NodeDB.new(target_node)
      
      ndb.sync     
      # Two events should fire up -- a sync to and from the server
      assert @event_log.length >= 2
      assert (@event_log.find {|log| old_log[log[2]].is_management}).length > 0
      assert (@event_log.find {|log| old_log[log[1]].is_management}).length > 0   
    end
    
    should "sync eventually to all" do
      # Ok this is going to be insane    
      # We test that eventually all nodes get some info
      first_node = nil
      1000.times do |i|
        target_node = get_random_node
        first_node = target_node if !first_node 
        ndb = NodeDB.new(target_node)
        ndb.sync
      end
      
      #Now we want to show that all running nodes go the information
      # if they called sync after the node updated
    
      tainted = {}
      @node_log.each do |n|
        tainted[n.name] = false
      end
      
      tainted[first_node.name] = true
      @event_log.each do |ev|
        from_node = ev[1]
        to_node = ev[2]
        tainted[to_node] |= tainted[from_node] 
      end
      
      # @node_log.each do |n|
      #  puts "#{n.name}: #{tainted[n.name]} (#{n.status})"
      # end
      
      assert @node_log.all? {|n| (n.status == "UNAVAILABLE") or tainted[n.name]}
      
    end
    
    
  end

end
