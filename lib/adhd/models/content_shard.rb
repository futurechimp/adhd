

class ContentShard
  attr_accessor :nodes, :this_shard, :our_node, :this_shard_db  

  def initialize(nodesv, this_shardv)
    @nodes = nodesv
    @this_shard = this_shardv
    
    # Work out the rest
    @our_node = nodesv.our_node
    @this_shard_db = nodesv.our_node.get_content_db(this_shardv.shard_db_name)
  end

  def in_shard?(internal_id)
     internal_id >= this_shard.range_start && internal_id < this_shard.range_end
  end

  def write_doc(content_doc)
    # Write a content document to this shard    
    # Make sure it is in this shard
    if in_shard? content_doc.internal_id
      this_shard_db.save_doc(content_doc)
    end
  end
  
  def sync
    # A Shard only pushes with the master of the shard
    # or the node with the highest is_storage value alive
    # Shard masters ensure changes are pushed to all    

    # NOTE: This method needs serious refactoring

    # Are we the shard master?
    am_master = false
    if our_node.name == this_shard.master_node
      am_master = true      
    end

    if !am_master
      begin
        master_node = Nodes.by_name(this_shard.master_node).first
        remotedb = master_node.get_content_db(this_shard.shard_db_name)
        this_shard_db.replicate_to(remote_db)
        return # We sync-ed so job is done
      rescue
        # We flag the master as unavailable
        if master_node
          master_node.status = "UNAVAILABLE"
          master_node.save
        end         
      end
    end
    
    # Either we are the master or the master has failed -- we replicate with 
    # all nodes or the first available aside us and master
    this_shard.node_list.each do |node_name|
       if !(our_node.name == node_name) && !(this_shard.master_node == node_name)
         begin
           # Push all changes to the other nodes
           remote_node = Nodes.by_name(node_name).first
           remotedb = remote_node.get_content_db(this_shard.shard_db_name)
           this_shard_db.replicate_to(remote_db)
           break if !am_master
         rescue
           # Make sure that the node exist in the DB and flag it as unresponsive
           if remote_node
             remote_node.status = "UNAVAILABLE"
             remote_node.save
           end         
         end
       end

    end    
  end
end

class ContentDoc < CouchRest::ExtendedDocument
  # NOTE: NO DEFAULT DATABASE IN THE OBJECT -- WE WILL BE STORING A LOT OF 
  # DATABASES OF THIS TYPE.

  property :internal_id
  property :size_bytes
  property :filenane
  property :mime_type
  
  view_by :internal_id
  
  # A special attachment "File" is expected to exist
end 