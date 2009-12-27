require 'rubygems'
require 'couchrest'
require 'ruby-debug'
require File.dirname(__FILE__) + '/models/node_doc'
require File.dirname(__FILE__) + '/models/content_doc'
require File.dirname(__FILE__) + '/models/shard_range'
require File.dirname(__FILE__) + '/models/content_shard'

module Adhd
  class NodeManager

    attr_accessor :our_node, :ndb, :srdb

    def initialize(config)
      @config = config
      @couch_server = CouchRest.new("http://#{config.node_url}:#{config.couchdb_server_port}")
      # @couch_server.default_database = "#{config.node_name}_node_db"
      @couch_db = @couch_server.database!("#{config.node_name}_node_db") # CouchRest::Database.new(@couch_server, "#{config.node_name}_node_db")
      sync_with_buddy_node if config.buddy_server_url && config.buddy_server_db_name
      @our_node = initialize_node
      build_node_admin_databases
      set_as_management_node_if_necessary
      build_shards(10, 2)
      build_node_content_databases
      sync_databases
    end

    def event_handler(ev)
      puts ev
    end

    # Sync the db with our buddy
    #
    def sync_with_buddy_node
      begin
        buddy_server = CouchRest.new("#{@config.buddy_server_url}")
        buddy_db = buddy_server.database!(@config.buddy_server_db_name + "_node_db")
        @couch_db.replicate_from(buddy_db)
      rescue
        puts "Could not buddy up with node #{@config.buddy_server_db_name}"
      end
    end

    # Retrieve our own node record from CouchDB by our name.
    #
    # If there are other nodes with the name kill their records!
    #
    def initialize_node
      puts "Initialize node #{@config.node_name}"
      Node.use_database @couch_db
      puts "DB #{@couch_db}, node #{@config.node_name}"
      node_candidates = Node.by_name(:key => @config.node_name)
      # node_candidates = @couch_db.view("by_name", {:key => @config.node_name})
      node = node_candidates.pop
      node = Node.new if node.nil?
      node_candidates.each do |other_me|
        other_me.destroy # destroy other records
      end
      # Update our very own record
      node.name = @config.node_name
      node.url = "http://#{@config.node_url}:#{@config.couchdb_server_port}"
      node.status = "RUNNING"
      node.save
      node # Save our node as instance variable
    end

    # We check if we are the first node. If we are the first node, we set
    # ourself up as the management node.
    #
    def set_as_management_node_if_necessary
      all_nodes = Node.by_name
      if all_nodes.length == 1
        @our_node.is_management = 300
        @our_node.save
      end
    end

    def build_node_admin_databases
      @conn_manager = ConnectionBank.new

      # Let's build a nice NodeDB
      @ndb = NodeDB.new(@our_node)
      conn_node = UpdateNotifierConnection.new(@config.node_url,
                                        @config.couchdb_server_port,
                                        @our_node.name + "_node_db", # NOTE: Sooo ugly!
                                        Proc.new {|data| handle_node_update data})
      @conn_manager.add_connection(conn_node)


      # Lets build a nice ShardDB
      @srdb = ShardRangeDB.new(@ndb)

      # Listen to the shard db and in case something changes re-build the DB
      # Chenges to the shards should be in-frequent and tolerable
      conn_shard = UpdateNotifierConnection.new(@config.node_url,
                                        @config.couchdb_server_port,
                                        @our_node.name + "_shard_db", # NOTE: Sooo ugly!
                                        Proc.new {|data| build_node_content_databases})
      @conn_manager.add_connection(conn_shard)

    end

    # A node changed status (became available, or became unavailable).
    #
    # If we are the admin, when a node joins we should allocate some shards to
    # it.
    #
    # Only the head management node deals with node changes.
    #
    #  XXXX doc question: what does it mean to be 'the admin'?
    #
    def handle_node_update update
      return if @ndb.head_management_node && ! (@ndb.head_management_node.name == @our_node.name)

      # Given the shard_db and the node_db we should work out a new allocation
      node_list = Node.by_name
      shard_list = ShardRange.by_range_start
      if node_list && shard_list
        assign_nodes_to_shards(node_list, shard_list, 2)
      end
    end


    # Build content shard databases.
    #
    def build_node_content_databases
      # NOTE: we will have to refresh those then we are re-assigned shards
      @contentdbs = {} if !@contentdbs
      current_shards = @srdb.get_content_shards

      # Add the new shards
      current_shards.each_key do |cs|
        if !(@contentdbs.has_key?(cs)) # Make sure we do not know of this shard
          shard_db = current_shards[cs]
          conn = UpdateNotifierConnection.new(@config.node_url,
                                          @config.couchdb_server_port,
                                          @our_node.name + "_" + shard_db.this_shard.shard_db_name + "_content_db", # NOTE: Sooo ugly!
                                          Proc.new { |data| shard_db.sync })
          @conn_manager.add_connection(conn)

          # Store both the shard object and the update notifier
          @contentdbs[cs] = [shard_db, conn]
        end
      end

      # Delete what we do not need
      @contentdbs.each_key do |cs|
        if !(current_shards.has_key?(cs))
          # Delete this shard from our DB
          remove_content_shard @contentdbs[cs][0], @contentdbs[cs][1]
          # Remove that key
          @contentdbs.delete cs
        end
      end
    end

    # Kills the connection listening for updates on this shard
    #
    # TODO: test if the sync happened
    # content_shard.this_shard_db.delete!
    # TODO: run a sync with the current master to ensure that
    #       any changes have been pushed. The DELETE the database
    #       to save space
    def remove_content_shard content_shard, connection
      connection.kill
      content_shard.sync
    end

    # Enters the eventmachine loop
    #
    def run
      @conn_manager.run_all
    end

    def build_shards(number_of_shards, number_of_replicators)
      if @our_node.is_management

        if ShardRange.by_range_start.length == 0
          puts "Creating new ranges"
          @srdb.build_shards(number_of_shards)
        end

        # Populate the shards with some nodes at random
        node_names = []
        all_nodes = Node.by_name
        all_nodes.each do |anode|
          node_names << anode.name
        end

        ShardRange.by_range_start.each do |s|
          if !s.node_list or s.node_list.length == 0
            node_names.shuffle!
            s.node_list = node_names[0..(number_of_replicators-1)]
            s.master_node = node_names[0]
            s.save
          end
        end
      end
    end

    def sync_databases
      @ndb.sync # SYNC
      @srdb.sync # SYNC

      @contentdbs.each_key do |cs|
        @contentdbs[cs][0].sync
      end
    end

    def sync_admin
        @ndb.sync # SYNC
        @srdb.sync # SYNC
    end

  end
end

# -------- Management node logic -------------------

require 'md5'

# This is an automatic way to allocate shards to nodes that just
# arrive in the networks, as well as re-allocate shards if nodes
# become unavailable or leave the network.
#
# NOTE: How to build skynet (Part III)
#
#       The invariant we try to impose on the list of nodes part of a shard
#       is that there should be at least replication_factor available nodes
#       in it. At the same time we try to keep the list stable over nodes
#       joining and leaving. To achieve this we hash in sequence the name of
#       each node with the name of the shard. We sort this list by hash, and
#       choose the first n nodes such that at least replication_factor nodes
#       are available. Then we chose the first available node as the master
#       for that shard.
#
def assign_nodes_to_shards(node_list, shard_range_list, replication_factor)

  shard_range_list.each do |shard_range|
    # Sort all nodes using consistent hashing
    sorted_nodes = node_list.sort_by {|node| MD5.new("#{node.name}||#{shard_range.shard_db_name}").to_s}
    avail = 0
    master = nil
    shard_node_list = []
    sorted_nodes.each do |node|
      shard_node_list << node
      if node.status == "RUNNING"
        master = node if !master # Chose the first available to be the master
        avail += 1
        break if avail == replication_factor # We have enough available nodes
      end
    end

    # Now put this list in the shard_range and save it
    # but only if there were changes
    new_master = master.name if master
    new_node_list = shard_node_list.map {|node| node.name}

    if !(new_master == shard_range.master_node) or !(new_node_list == shard_range.node_list)
      shard_range.master_node = master.name if master
      shard_range.node_list = shard_node_list.map {|node| node.name}
      shard_range.save
    end
  end

end

