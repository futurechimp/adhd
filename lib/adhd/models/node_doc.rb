## Key Restrictions ok internal_IDs: must only contain [a-z0-9-]

class NodeDB

  attr_accessor :local_node_db, :our_node

  def initialize(our_nodev)
    @our_node = our_nodev

    # Get the address of the CDB from the node
    @local_node_db = our_nodev.get_node_db
  end

  # Syncs this management node with other existing management nodes by looping
  # through all known management nodes.
  #
  # If replication to or from any management node fails, the method breaks
  # and continues replicating to other management nodes until all management
  # nodes have been tried.
  #
  # NOTE: randomize the order for load balancing here
  #
  # NOTE2: How to build skynet (TODO)
  #        -------------------
  #        If length of management is zero, then chose 3 different random
  #        nodes at each sync, and sync with them in node_name order.
  #        This guarantees that any updates on nodes are communicated in
  #        O(log N) ephocs, at the cost of O(3 * N) connections per epoch.
  #        It also guarantees any new management servers are discovered in
  #        this O(log N) time, creating "jelly fish" or "partition proof"
  #        availability.
  def sync
    # We replicate our state to the management node(s)
    management_nodes = Node.by_is_management.reverse

    management_nodes.each do |mng_node|
      remote_db = mng_node.get_node_db
      from_success = @our_node.replicate_from(local_node_db, mng_node, remote_db)
      to_success = @our_node.replicate_to(local_node_db, mng_node, remote_db)
      if from_success && to_success && !our_node.is_management
         break
      end
    end
  end

  # Returns all nodes marked as available
  #
  def available_node_list
    all_nodes = Node.by_name
    return all_nodes.select {|node| node.status == "RUNNING"}
  end

  # Returns the first RUNNING management node.  There is no real dependency on
  # any specific node, this is just a way for all nodes to agree on the same
  # node to do the job of the head management node.
  #
  def head_management_node
    management_nodes = Node.by_is_management.reverse
    hmn = management_nodes.find {|node| node.status == "RUNNING"}
    return hmn
  end

end

class Node  < CouchRest::ExtendedDocument
  unique_id :name

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
  end

  def get_shard_db
    server = CouchRest.new("#{url}")
    db = server.database!("#{name}_shard_db")
  end

  def get_content_db(shard_db_name)
    server = CouchRest.new("#{url}")
    db = server.database!("#{name}_#{shard_db_name}_content_db")
  end

  # Replicating databases and marking nodes as unavailable
  # In the future we should hook these into a "replication manager"
  # for databases. The manager should set up continuous replication across
  # databases, and only do a replication after some time lapses.

  def replicate_to(local_db, other_node, remote_db)
    replicate_to_or_from(local_db, other_node, remote_db, true)
  end

  def replicate_from(local_db, other_node, remote_db)
    replicate_to_or_from(local_db, other_node, remote_db, false)
  end

  private

  # Replicates to or from a management node database.  The direction of
  # replication is controlled by a boolean property.
  #
  # Returns true if replication succeeds, false if not.
  #
  def replicate_to_or_from(local_db, other_node, remote_db, to = true)
    # Do not try to contact unavailable nodes
    return false if other_node.status == "UNAVAILABLE"
    # No point replicating to ourselves
    return false if (name == other_node.name)

    begin
      # Replicate to other node is possible
      if to
        local_db.replicate_to(remote_db)
      else
        local_db.replicate_from(remote_db)
      end
      return true
    rescue Exception => e
      # Other node turns out to be unavailable
      other_node.status = "UNAVAILABLE"
      other_node.save
      return false
    end

  end


end

