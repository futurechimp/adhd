# Models a CouchDB database which holds ShardRange documents.
#
class ShardRangeDb

  attr_accessor :nodes, :local_shard_db, :our_node

  def initialize(nodesv)
    @nodes = nodesv

    # Automatically get our shard_db address from our own node name
    @our_node = nodesv.our_node
    @local_shard_db = nodesv.our_node.get_shard_db

    puts "Assign default database for shard ranges (#{@local_shard_db})"
    ShardRange.use_database @local_shard_db
  end

  def sync

    # We replicate our state from the management node(s)
    # We never push content if we are only storage
    management_nodes = Node.by_is_management.reverse

    # NOTE: randomize the order for load balancing here

    management_nodes.each do |mng_node|
      remote_db = mng_node.get_shard_db
      bool_from = @our_node.replicate_from(local_shard_db, mng_node, remote_db)
      if our_node.is_management
        # Push any changes to other management nodes
        bool_to = @our_node.replicate_to(local_shard_db, mng_node, remote_db)
      end
      break if bool_from && !our_node.is_management
    end
  end

  def build_shards(number)
    # Make a large list of possible id boundaries
    characters = []
    ("0".."9").each do |c|
      characters << c
    end
    ("a".."f").each do |c|
      characters << c
    end

    # Generate 36 x 36 keys to choose boundaries from
    all_keys = []
    characters.each do |c1|
      characters.each do |c2|
        characters.each do |c3|
          all_keys << (c1+c2+c3)
        end
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
    shard_ends << ("z" * 3)
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
    content_shards = {}
    ShardRange.by_node(:key => our_node.name).each do |s|

      # Build a content shard object
      content_shards[s.shard_db_name] = ContentShard.new(nodes, s)
    end
    puts "Content shards #{content_shards.length}"
    content_shards
  end

  def write_doc_directly(content_doc)
    # Write a document directly to a nodes content repository
    success = {:ok => false , :reason => "No available node found"}
    doc_shard = get_shard(content_doc.internal_id).first
    doc_shard.get_nodes.each do |node|
      # Try to write the doc to this node
      begin
        remote_node = Node.by_name(:key => node).first

        # Do not contact unavailable nodes
        next if remote_node.status == "UNAVAILABLE"
        remote_ndb = NodeDB.new(remote_node)

        remote_content_shard = ContentShard.new(remote_ndb, doc_shard)
        remote_content_shard.this_shard_db.save_doc(content_doc)
        success = {:ok => true, :doc => content_doc, :db => remote_content_shard.this_shard_db}
        break
      rescue RestClient::RequestFailed => rf

        if rf.http_code == 409
          debugger
          puts "Document already there"
          puts rf.to_json
          return {:ok => false , :reason => "Document already in database"}
        end
      rescue Exception =>e
        puts "Could not put doc in node #{node} because of #{rf}"
        # TODO: change status or chose another management server
        remote_node.status = "UNAVAILABLE"
        remote_node.save
      end
    end
    return success
  end

  def get_doc_directly(internal_id)
    # Write a document directly to a nodes content repository
    doc_shard = get_shard(internal_id).first

    # TODO: Randomize the order of nodes for load balancing in retrieval!
    docx = []
    doc_shard.get_nodes.each do |node|
      # Try to write the doc to this node
      begin
        remote_node = Node.by_name(:key => node).first
        remote_ndb = NodeDB.new(remote_node)
        remote_content_shard = ContentShard.new(remote_ndb, doc_shard)

        docx = ContentDoc.by_internal_id(:key => internal_id, :database => remote_content_shard.this_shard_db)
        if docx.length > 0
          return {:ok => true, :doc => docx.first, :db => remote_content_shard.this_shard_db }
        end
      rescue
        puts "Could not put doc in node #{node.name}"
        # TODO: change status or chose another management server
        remote_node.status = "UNAVAILABLE"
        remote_node.save
      end
    end
  return {:ok => false }
  end

end

