
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
        remote_db.replicate_from(local_db)
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

