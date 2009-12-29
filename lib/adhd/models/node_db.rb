# Models a CouchDB node management database containing node descriptors
# for the cluster. TODO: once we have some better tests in place, think about
# renaming this class and refactoring.
#
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
  # TODO: randomize the order for load balancing here
  #
  # NOTE2: How to build skynet (TODO)
  #
  # If length of management is zero, then choose 3 different random
  # nodes at each sync, and sync with them in node_name order.
  #
  # This guarantees that any updates on nodes are communicated in
  # O(log N) ephocs, at the cost of O(3 * N) connections per epoch.
  #
  # It also guarantees any new management servers are discovered in
  # this O(log N) time, creating "jelly fish" or "partition proof"
  # availability.
  #
  def sync
    # We replicate our state to the management node(s)
    management_nodes = find_management_nodes
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

  # Returns a list of management nodes. This is a bit of a hack, it's really
  # only here so that we can override the method in a subclass for testing
  # purposes (SEE: test_node_db).
  #
  def find_management_nodes
    management_nodes = Node.by_is_management.reverse
  end

end

