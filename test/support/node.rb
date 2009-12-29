class Node
  def initialize event_log
    @event_log = event_log
  end

  attr_accessor :status, :name, :is_management

  def self.set_nodes nodes
    @@nodes = nodes
  end

  def self.by_is_management
    # Return a random set of nodes
    @@nodes.select {|n| n.is_management && n.is_management > 0}
  end

  def get_node_db
    @name
  end

  def replicate_to(local_db, other_node, remote_db)
    return false if other_node.status == "UNAVAILABLE" or other_node.name == name
    @event_log << [:rep, local_db, remote_db]
    true
  end

  def replicate_from(local_db, other_node, remote_db)
    return false if other_node.status == "UNAVAILABLE" or other_node.name == name
    @event_log << [:rep, remote_db, local_db]
    true
  end

end

