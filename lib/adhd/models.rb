# Key Restrictions ok internal_IDs: must only contain [a-z0-9-]

class NodeDB
  attr_accessor :local_node_db, :our_node

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
      puts "Sync NodeDB with #{mng_node.name}"
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

  def get_shard_db
    server = CouchRest.new("#{url}")
    server.database!("#{name}_shard_db")
  end  
  
  def get_content_db(shard_db_name)
    server = CouchRest.new("#{url}")
    server.database!("#{name}_#{shard_db_name}_content_db")
  end  
end

class ShardRangeDB

  attr_accessor :nodes, :local_shard_db, :our_node  

  def sync
    # We replicate our state from the management node(s)
    # We never push content if we are only storage
    management_nodes = Node.by_is_management.reverse
    # NOTE: randomize the order for load balancing here
    
    
    management_nodes.each do |mng_node|      
      remote_db = mng_node.get_shard_db
      if !(mng_node.name == our_node.name)
        begin 
          puts "Sync ShardRange DB pull from #{mng_node.name}"
          local_shard_db.replicate_from(remote_db)
          # TODO: Manage conflicts here          
          if our_node.is_management 
            # Push any changes to other management nodes
            puts "Sync ShardRange DB pushto #{mng_node.name}"
            local_shard_db.replicate_to(remote_db)
          else
            break # sync with only one management server
        end
        rescue
          puts "Could not connect to DB node #{mng_node.name}"
          # TODO: change status or chose another management server
          mng_node.status = "UNAVAILABLE"
          mng_node.save
        end     
      end
    end
  end 

  def build_shards(number)
    # Make a large list of possible id boundaries
    characters = []
    ("0".."9").each do |c|
      characters << c
    end
    ("a".."z").each do |c|
      characters << c
    end
    
    # Generate 36 x 36 keys to choose boundaries from
    all_keys = []
    characters.each do |c1|
      characters.each do |c2|
        all_keys << (c1+c2)
      end
    end
    
    # Now chose our boundaries
    num_range_keys = all_keys.length
    approx_shard_size = (num_range_keys * 1.0) / number
    
    shard_starts = []
    (0...number).each do |n|
      shard_starts << (all_keys[(n * approx_shard_size).floor])
    end
    
    shard_ends = shard_starts.clone
    shard_ends << ("z" * 100)
    shard_ends.delete_at(0)
    
    # Finally build them!
    puts "Build Shards"
    (0...number).each do |n|
      puts "Shard #{n}: from #{shard_starts[n]} to #{shard_ends[n]}"
      shard_name = "sh_#{shard_starts[n]}_to_#{shard_ends[n]}"
      sr = ShardRange.new
      sr.range_start = shard_starts[n]
      sr.range_end = shard_ends[n]
      sr.shard_db_name = shard_name
      sr.save
    end    
  end

  def get_shard(internal_id)
    # Finds the list of shards within which this ID lives
    all_shards = ShardRange.by_range_start 
    selected_shards = []
    all_shards.each do |a_shard| # TODO: linear search is inefficient -- create a view 
      if a_shard.range_start <= internal_id && a_shard.range_end > internal_id
        selected_shards << a_shard
      end
    end
    selected_shards
  end
  
  def get_content_shards
    # Return the content_shards of our node
    content_shards = []
    ShardRange.by_node(:key => "node1").each do |s|
      
      # Build a content shard object
      cs = ContentShard.new
      cs.our_node = our_node
      cs.this_shard = s
      cs.nodes = nodes
      cs.this_shard_db = our_node.get_content_db(s.shard_db_name)
      
      # add it to the list
      content_shards << cs
    end
    content_shards
  end
  
  

end

class ShardRange < CouchRest::ExtendedDocument
  SHARDSERVER = CouchRest.new("#{ARGV[1]}")
  SHARDSERVER.default_database = "#{ARGV[0]}_shard_db"

  use_database SHARDSERVER.default_database

  property :range_start
  property :range_end
  property :node_list
  property :master_node
  property :shard_db_name

  view_by :range_start 
  
  # View "node" - given a node returns the shards watched
  # How to use this new
  # 
  # puts "Which Shards does 'node1' watch?"
  # ShardRange.by_node(:key => "node1").each do |s|
  #   puts "Shard: #{s.shard_db_name}"
  # end

   
  view_by :node,
          :map => 
          "function(doc) {
          if (doc['couchrest-type'] == 'ShardRange' && doc.node_list) {
            doc.node_list.forEach(function(node){
              emit(node, 1);
            });
          }
        }"  

end


class ContentShard
  attr_accessor :nodes, :this_shard, :our_node, :this_shard_db

  def in_shard?(internal_id)
     internal_id >= this_shard.range_start && internal_id < this_shard.range_end
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
        remotedb = MASTER_node.get_content_db(this_shard.shard_db_name)
        this_shard_db.replicate_to(remote_db)
        return # We sync-ed so job is done
      rescue
        # We flag the master as unavailable
        if remote_node
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
  
  # A special attachment "File" is expected to exist
end 
