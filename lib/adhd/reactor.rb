require 'rubygems'
require 'eventmachine'

module  Adhd

  # This module gets mixed into the EventMachine reactor loop, and sends events
  # to our Adhd::Node which is hanging around waiting for stuff to happen.
  #
  # Currently it just illustrates the fact that we can fire up an EventMachine
  # and have this reactor get mixed in as glue code to our Node.
  #
  # A call like:
  #     EM.start_server '192.168.1.104', 10000, Adhd::UnusedReactor, @node
  #
  # inside the EM.run block will start a server on port 10000 when we need a
  # server to do something for us. We can then change it into maybe a file
  # streaming server or whatever we need.
  #
  module UnusedReactor

    def initialize(node)
      puts "Something connected to our server..."
      @node = node
    end

    def receive_data data
      @node.event_handler("received event: #{data}")
    end

  end

  # A notifier client that makes a long-running request to a CouchDB instance
  # on a socket and continually sends any update notifications that it
  # receives back to its @node.
  #
  module DbUpdateNotifier

    def initialize(db_name, conn_obj)
      puts "Db update notifier start..."
      @db_name = db_name
      @conn_obj = conn_obj
      @buffer = ""
    end

    # Makes a long-running request to a CouchDB instance's _changes URL.
    #
    def post_init
      # NOTE: full domain name needed for virtual hosting
      req = "GET #{@conn_obj.base_url}/#{@db_name}/_changes?feed=continuous&heartbeat=5000\r\n\r\n"
      puts req
      send_data req
    end

    # Shoots update notifications from CouchDB to the @conn.
    #
    def receive_data data      
      # puts "received_data: #{data}"
      # puts "||#{data}||length=#{data.length}||#{data.dump}||"
      
      @buffer += data # Add the data to the current buffer
      updates = []
      if @buffer =~ /(\{[^\n]+\}\n)/
        updates += $~.to_a
        # Trim the buffer to $_.end(0)
        @buffer = @buffer[$~.end(0)..-1]
      end
      
      # Regexp for JSON updates is /\{[\n]\}+/
      updates.each do |json_event|
        @conn_obj.event_handler(json_event) unless data == "\n"
      end
    end

    def close_connection
      @conn_obj.close_handler(data)
    end

  end


  # Note: Some of manos's thoughts on how to manage our connections and events.
  #       We should build a class called connection_manager that we ask to build
  #       and listen to connections, as well as route events. Its job is to
  #       re-open them if they are closed or times out, mark nodes as UNAVAILABLE
  #       and notify us back when data (i.e. an update) arrives. It would also be
  #       nifty if each connection was associated with a predicate: once this
  #       predicate is false we can simply close the connection. For example upon
  #       being given control of a different content shard, or a different master
  #       for the shard.

  # In practice we will have two types of connections: Replicate and Notify.

  class UpdateNotifierConnection
    attr_accessor :db_name, :base_url

    def initialize(node_url, couchdb_server_port, db_name, db_obj_for_sync)
      @node_url = node_url
      @couchdb_server_port = couchdb_server_port
      @db_name = db_name
      @db_obj_for_sync = db_obj_for_sync
      @status = "NOTRUNNING"
      @base_url = "http://#{@node_url}:#{@couchdb_server_port}"
    end

    def start
      puts "Register the connection for #{@db_name}"
      EM.connect @node_url, @couchdb_server_port, Adhd::DbUpdateNotifier, @db_name, self
      @status = "RUNNING"
    end

    def event_handler data
      # puts "||#{data}||nn"
      puts "Run a crazy sync on db #{@db_name}"
      @db_obj_for_sync.sync
    end

    def close_handler
      puts "Closed abnormally #{reason}"
      @status = "NOTRUNNING"
    end

    def down_for_good(reason)
      if reason
        puts "Closed for good #{reason}"
      end
    end

    def keep_alive?
      # Returns the truth value of the predicate
      true
    end

    def should_start?
      !(@status == "RUNNING")
    end

    def is_closed?
      (@status == "NOTRUNNING")
    end


  end

  class Connection
    #def on_teardown(&block)
    #  # Set the handler to be called then a connection is dead
    #  block(self) # Run the teardown handler
    #end

    def should_start?
      !(@status == "RUNNING")
    end

    def is_closed?
      (@status == "NOTRUNNING")
    end

  end

  class ConnectionBank
    # Manage a bunch of connections for us
    def initialize
      @our_connections = []
    end

    def add_connection(conn)
      # If it is happy to run, add it to the list and start it!
      if conn.keep_alive?
          @our_connections << conn
          # Register the teardown handler for when the end comes...
          # conn.on_teardown(|c| { rerun(c) })
      end
    end

    def rerun(conn)
      # When a connection is down, we check to see if it wants to be kept
      # alive, and restart it otherwise we remove it from the list.
      if conn.keep_alive?
        begin
          conn.start
        rescue Exception => e
          conn.down_for_good(e)
        end
      else
        # It seems we have died of natural causes
        # XXX: is it true that Ruby does not throw and exception for EOF?
        #      Otherwise we will never see this
        @our_connections.delete(conn)
        conn.down_for_good(nil)
      end

    end

    def run_all
      # Go through all connections and run them all
      # Run within EM.run loop
      puts "Connection bank runs all... (#{@our_connections.length} connections)"
      @our_connections.each do |c|
        if c.is_closed?
          # puts "Actually start #{c.db_name}..."
          rerun(c)
        end
      end

    end

  end

end

