# Models a CouchDB database which contains lots and lots of ContentDoc objects.
#
class ContentShard
  attr_accessor :nodes, :this_shard, :our_node, :this_shard_db

  def initialize(nodesv, this_shardv)
    @nodes = nodesv
    @this_shard = this_shardv

    # Work out the rest
    @our_node = nodesv.our_node
    @this_shard_db = nodesv.our_node.get_content_db(this_shardv.shard_db_name)

    @last_sync_seq = 0 # @this_shard_db.info['update_seq']
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

  def sync all = false
    # A Shard only pushes with the master of the shard
    # or the node with the highest is_storage value alive
    # Shard masters ensure changes are pushed to all

    # NOTE: This method needs serious refactoring
    # No need to update
    return false if !all and @this_shard_db.info['update_seq'] == @last_sync_seq

    # Are we the shard master?
    am_master = (our_node.name == this_shard.master_node)

    if !am_master
      master_node = Node.by_name(:key => this_shard.master_node).first
      remote_db = master_node.get_content_db(this_shard.shard_db_name)
      bool_to = @our_node.replicate_to(this_shard_db, master_node, remote_db, false)
      bool_to &= @our_node.replicate_from(this_shard_db, master_node, remote_db, false)
      puts "Replicate #{this_shard.shard_db_name} from/to master #{master_node.name}" if bool_to
      if bool_to
        @last_sync_seq = @this_shard_db.info['update_seq']
        return true
      end
    end

    # Either we are the master or the master has failed -- we replicate with
    # all nodes or the first available aside us and master
    all_good = true
    this_shard.node_list.each do |node_name|
      # Do not sync with ourselves
      next if (@our_node.name == node_name)

       # Push all changes to the other nodes
       remote_node = Node.by_name(:key =>  node_name).first
       remote_db = remote_node.get_content_db(this_shard.shard_db_name)
       bool_to = @our_node.replicate_to(this_shard_db, remote_node, remote_db, false)
       bool_to &= @our_node.replicate_from(this_shard_db, remote_node, remote_db, false)
       puts "Replicate #{this_shard.shard_db_name} from/to #{remote_node.name}" if bool_to
       all_good &= bool_to
       if !am_master && bool_to
         # NOTE: How to build skynet, Note 2
         #       We are doing some "gonzo" replication, here. Our master is
         #       clearly down so we find the second best node; we push our
         #       changes to this node, and now also *replicate from*
         #       that node.         
         @last_sync_seq = @this_shard_db.info['update_seq']
         break
       end
    end
    if all_good
      @last_sync_seq = @this_shard_db.info['update_seq']
      return true
    else
      return false
    end
  end

end

class ContentDoc < CouchRest::ExtendedDocument
  # NOTE: NO DEFAULT DATABASE IN THE OBJECT -- WE WILL BE STORING A LOT OF
  # DATABASES OF THIS TYPE.

  property :_id
  property :internal_id
  property :size_bytes
  property :filename
  property :mime_type

  view_by :internal_id

  # A special attachment "File" is expected to exist

end

