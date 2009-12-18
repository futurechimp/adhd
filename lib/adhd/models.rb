class NodeDB
  attr_accessor :local_node_db, :our_node

  def sync
    # If not, we find out where the management node is and
    # we replicate to the administrative node.
    if !our_node.is_management
      management_node = Node.by_is_management.last
      remote_db = management_node.get_node_db
      local_node_db.replicate_from(remote_db)
      # TODO: Manage conflicts here
      local_node_db.replicate_to(remote_db) 
    else
      # Take all the management nodes with the same priority as us
      all_management_nodes = Node.by_is_management(our_node.is_management)
     
      # TODO: Manage conflicts here
      all_management_nodes.each do |mng_node|
         if ! (mng_node.name == our_node.name)
           local_node_db.replicate_from(mng_node.get_node_db)
           local_node_db.replicate_to(mng_node.get_node_db)
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

