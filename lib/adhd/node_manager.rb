require 'rubygems'
require 'couchrest'
require 'ruby-debug'
# require File.dirname(__FILE__) + '/models'
require File.dirname(__FILE__) + '/models/node_doc'
require File.dirname(__FILE__) + '/models/shard_range'
require File.dirname(__FILE__) + '/models/content_shard'

module Adhd
  class NodeManager

    def initialize(config)
      @config = config
      @couch_server = CouchRest.new("http://#{config.node_url}:#{config.couchdb_server_port}")
      # @couch_server.default_database = "#{config.node_name}_node_db"
      @couch_db = CouchRest::Database.new(@couch_server, "#{config.node_name}_node_db")
      sync_with_buddy_node if config.buddy_server_url && config.buddy_server_db_name
      @our_node = initialize_node
      set_as_management_node_if_necessary
      build_node_databases
      build_shards
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
        buddy_db = CouchRest::Database.new(buddy_server, @config.buddy_server_db_name + "_node_db")
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
        @our_node.is_management = 3
        @our_node.save
      end
    end

    def build_node_databases
      # Lets build a nice NodeDB
      @ndb = NodeDB.new(@our_node)

      # Lets build a nice ShardDB
      @srdb = ShardRangeDB.new(@ndb)

      # Get all content shard databases
      # NOTE: we will have to refresh those then we are re-assigned shards
      @contentdbs = @srdb.get_content_shards

      @conn_manager = ConnectionBank.new
      @contentdbs.each do |content_shard|
        conn = UpdateNotifierConnection.new(@config.node_url, 
                                        @config.couchdb_server_port, 
                                        @our_node.name + "_" + content_shard.this_shard.shard_db_name + "_content_db", # NOTE: Sooo ugly!
                                        content_shard)
        @conn_manager.add_connection(conn)
        puts "Observing DB #{content_shard.this_shard.shard_db_name}"      
        break # DEBUG -- REMOVE LATER
      end

    end
    
    def run
      @conn_manager.run_all
    end

    def build_shards
      if @our_node.is_management

        if ShardRange.by_range_start.length == 0
          puts "Creating new ranges"
          @srdb.build_shards(100)
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
            s.node_list = node_names[0..2]
            s.master_node = node_names[0]
            s.save
          end
        end
      end
    end

    def sync_databases
      @ndb.sync # SYNC
      @srdb.sync # SYNC

      @contentdbs.each do |content_shard_db|
        content_shard_db.sync
      end
    end

  end
end

