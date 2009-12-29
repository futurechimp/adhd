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
      # puts "Db update notifier start..."
      @db_name = db_name
      @conn_obj = conn_obj
      @buffer = ""
      conn_obj.connection_inside = self # We tell the outer object who we are
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
        updates += ($~.to_a)[1..-1]
        # Trim the buffer to $_.end(0)
        @buffer = @buffer[$~.end(0)..-1]
      end

      # Regexp for JSON updates is /\{[\n]\}+/
      updates.each do |json_event|
        @conn_obj.event_handler(json_event) unless data == "\n"
      end
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
  #
  # In practice we will have two types of connections: Replicate and Notify.
  #
  class UpdateNotifierConnection
    attr_accessor :db_name, :base_url, :connection_inside, :name

    def initialize(node_url, couchdb_server_port, db_name, sync_block)
      @node_url = node_url
      @couchdb_server_port = couchdb_server_port
      @db_name = db_name
      @sync_block = sync_block
      @status = "NOTRUNNING"
      @base_url = "http://#{@node_url}:#{@couchdb_server_port}"
      @name = @base_url +"/"+ @db_name
      @keep_alive = true
    end

    def kill clean_up_op
      @keep_alive = false
      @clean_up_op = clean_up_op
      keep_alive_or_kill!
    end

    def start
      #puts "Registering the connection for: #{@db_name}"
      EM.connect @node_url, @couchdb_server_port, Adhd::DbUpdateNotifier, @db_name, self
      @status = "RUNNING"
    end

    def event_handler data
      #puts "Run a crazy sync on db: #{@db_name}"
      @sync_block.call(data)
    end

    def close_handler
      #puts "Closed abnormally: #{reason}"
      @status = "NOTRUNNING"
    end

    def down_for_good(reason)
      if reason
        puts "Closed for good: #{reason}"
      end
    end

    # Returns the truth value of the predicate
    #
    def keep_alive?
      @keep_alive
    end

    def keep_alive_or_kill!
      if ! keep_alive?
        # Schedule this connection for close
        connection_inside.close_connection_after_writing
        @status = "NOTRUNNING"
      end
    end

    def should_start?
      !(@status == "RUNNING")
    end

    def is_closed?
      (@status == "NOTRUNNING")
    end
    
    def unbind
      @clean_up_op.call if @clean_up_op
    end

  end
  
  
  # Manage a bunch of connections for us
  #
  class ConnectionBank

    def initialize
      @our_connections = []
    end

    # Add a connection to the ConnectionBank, making sure we have no duplicates.
    #
    def add_connection(conn)
      @our_connections.each do |c|
        if conn.name == c.name
          return
        end
      end

      # If it is happy to run, add it to the list and start it!
      #
      if conn.keep_alive?
          @our_connections << conn
          # Register the teardown handler for when the end comes...
          # conn.on_teardown(|c| { rerun(c) })
      end
    end

    # When a connection is down, we check to see if it wants to be kept
    # alive, and restart it; otherwise we remove it from the list.
    #
    def rerun(conn)
      if conn.keep_alive?
        begin
          conn.start
        rescue Exception => e
          conn.down_for_good(e)
        end
      else
        # It seems we have died of natural causes
        # XXX: is it true that Ruby does not throw an exception for EOF?
        #      Otherwise we will never see this
        conn.keep_alive_or_kill!
        @our_connections.delete(conn)
        conn.down_for_good(nil)
      end

    end

    # Go through all connections and run them all
    # Run within EM.run loop
    #
    def run_all
      @our_connections.each do |c|
        if c.is_closed? or !c.keep_alive?
          #puts "Actually rerun #{c.db_name}..."
          rerun(c)
        end
      end

    end

  end

end

