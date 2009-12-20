require 'rubygems'
require 'couchrest'
require 'ruby-debug'
require File.dirname(__FILE__) + '/models'

module Adhd
  class NodeManager

    def initialize(config)
      @config = config
      @couch_server = CouchRest.new("#{config.node_url}:#{config.couchdb_server_port}")
      @couch_server.default_database = "#{config.node_name}_node_db"
      @couch_db = CouchRest::Database.new(@couch_server, "#{config.node_name}_node_db")
      sync_with_buddy_node if config.buddy_server_url && config.buddy_server_db_name
      initialize_node
      set_as_management_node_if_necessary
      build_node_databases
      sync_databases
    end

    def event_handler(ev)
      puts ev
    end

    # Sync the db with our buddy
    #
    def sync_with_buddy_node
      buddy_server = CouchRest.new("#{@config.buddy_server_url}")
      buddy_db = CouchRest::Database.new(buddy_server, @config.buddy_server_db_name + "_node_db")
      @couch_db.replicate_from(buddy_db)
    end

    # Retrieve our own node record from CouchDB by our name.
    #
    # If there are other nodes with the name kill their records!
    #
    def initialize_node
      node_candidates = ::Node.by_name(:key => @config.node_name)
      node = node_candidates.pop
      node = Node.new if node.nil?
      node_candidates.each do |other_me|
        other_me.destroy # destroy other records
      end
      # Update our very own record
      node.name = node_name
      node.url = node_url
      node.status = "RUNNING"
      node.save
    end

    # We check if we are the first node. If we are the first node, we set
    # ourself up as the management node.
    #
    def set_as_management_node_if_necessary
      all_nodes = Node.by_name
      if all_nodes.length == 1
        node.is_management = 3
        node.save
      end
    end

    def build_node_databases
      # Lets build a nice NodeDB
      @ndb = NodeDB.new(node)

      # Lets build a nice ShardDB
      @srdb = ShardRangeDB.new(ndb)

      if ShardRange.by_range_start.length == 0 && node.is_management
        puts "Creating new ranges"
        @srdb.build_shards(100)
      end

      # Populate the shards with some nodes at random
      node_names = []
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

    def sync_databases
      ndb.sync # SYNC
      srdb.sync # SYNC

      srdb.get_content_shards.each do |content_shard_db|
        content_shard_db.sync
      end
    end

  end
end

