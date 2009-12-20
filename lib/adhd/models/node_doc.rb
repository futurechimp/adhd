## Key Restrictions ok internal_IDs: must only contain [a-z0-9-]

class NodeDB
  
  attr_accessor :local_node_db, :our_node
  
  def initialize(our_nodev)
    @our_node = our_nodev
    
    # Get the address of the CDB from the node
    @local_node_db = our_nodev.get_node_db
  end
  
  def sync
    # We replicate our state to the management node(s)
    management_nodes = Node.by_is_management.reverse
    # NOTE: randomize the order for load balancing here

    # NOTE2: How to build skynet (TODO)
    #        -------------------
    #        If length of management is zero, then chose 3 different random
    #        nodes at each sync, and sync with them in node_name order.
    #        This guarantees that any updates on nodes are communicated in
    #        O(log N) ephocs, at the cost of O(3 * N) connections per epoch.
    #        It also guarantees any new management servers are discovered in
    #        this O(log N) time, creating "jelly fish" or "partition proof"
    #        availability. 
    
    management_nodes.each do |mng_node|
      remote_db = mng_node.get_node_db
      if !(mng_node.name == our_node.name)
        begin 
          
          local_node_db.replicate_from(remote_db)
          # TODO: Manage conflicts here
          local_node_db.replicate_to(remote_db)
          break if !our_node.is_management # Only need to contact one node
        rescue
          puts "Could not connect to DB node #{mng_node.name}"
          # TODO: change status or chose another management server
          mng_node.status = "UNAVAILABLE"
          mng_node.save
        end     
      end
    end
  end 

end

class Node  < CouchRest::ExtendedDocument
  #NODESERVER = CouchRest.new("#{ARGV[1]}")
  #NODESERVER.default_database = "#{ARGV[0]}_node_db"

  #use_database NODESERVER.default_database

  property :name
  property :url
  property :is_store
  property :is_management
  property :is_directory
  property :status

  timestamps!

  view_by :name
  view_by :is_management

  def get_node_db
    server = CouchRest.new("#{url}")
    db = server.database!("#{name}_node_db")
    puts "Open db #{db}"
    db
  end

  def get_shard_db
    server = CouchRest.new("#{url}")
    db = server.database!("#{name}_shard_db")
    puts "Open db #{db}"
    db
  end  
  
  def get_content_db(shard_db_name)
    server = CouchRest.new("#{url}")
    db = server.database!("#{name}_#{shard_db_name}_content_db")
    puts "Open db #{db}"
    db
  end  
end

