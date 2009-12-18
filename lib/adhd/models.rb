class NodeDB
  attr_accessor :local_node_db, :our_node

  def sync
    # We replicate our state to the management node(s)
    management_nodes = Node.by_is_management.reverse
    # NOTE: randomize the order for load balancing here
    
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
  NODESERVER = CouchRest.new("#{ARGV[1]}")
  NODESERVER.default_database = "#{ARGV[0]}_node_db"

  use_database NODESERVER.default_database

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
    server.database!("#{name}_node_db")
  end
end

class ShardRange < CouchRest::ExtendedDocument
  NODESERVER = CouchRest.new("#{ARGV[1]}")
  NODESERVER.default_database = "#{ARGV[0]}_shard_db"

  use_database NODESERVER.default_database

  property :range_start
  property :range_end
  property :node_list
  property :master_node
  property :shard_db_name
  
end

