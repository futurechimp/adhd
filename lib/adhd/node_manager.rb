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
        @our_node.is_management = 3
        @our_node.save
      end
    end

    def build_node_admin_databases      
      @conn_manager = ConnectionBank.new

      # Lets build a nice NodeDB
      @ndb = NodeDB.new(@our_node)
      conn_node = UpdateNotifierConnection.new(@config.node_url, 
                                        @config.couchdb_server_port, 
                                        @our_node.name + "_node_db", # NOTE: Sooo ugly!
                                        Proc.new {|data| handle_node_update update})
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
    
    def handle_node_update update
      # Added, removed or changed the status of a node
    end
    
    
    def build_node_content_databases
      # Get all content shard databases
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
    
    def remove_content_shard content_shard, connection
      # Kill the connection listening for updates on this shard
      connection.kill      
      content_shard.sync
      # TODO: test if the sync happened
      shard_db.this_shard_db.delete
      # TODO: run a sync with the current master to ensure that
      #       any changes have been pushed. The DELETE the database
      #       to save space    
    end
    
    def run
      # Enters the event machine loop
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

