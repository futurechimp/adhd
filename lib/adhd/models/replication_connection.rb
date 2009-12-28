

module  Adhd

  module ReplicationNotifier

    def initialize(conn_obj)      
      @conn_obj = conn_obj
      @buffer = ""
      conn_obj.connection_inside = self # We tell the outer object who we are
      # pending_connect_timeout= 5.0
    end

    # Makes a long-running request to a CouchDB instance
    # Implement PULL replication, as it is most efficient 
    # in CouchDB 0.9
    #
    def post_init 
      # Build a JSON representation
      r = {:source => "#{@conn_obj.remote_db}",
           :target => "#{@conn_obj.our_db}"}
           #, :continuous => true }
      r_json = r.to_json

      # Create the HTTP request
      req = "POST /_replicate HTTP/1.1\r\n"
      req += "Content-Length: #{r_json.length}\r\n\r\n"      
      req += "#{r_json}"
      
      # Push it to the network
      send_data req
    end

    # Shoots replication events from CouchDB to the @conn.
    # Buffers data until a JSON object is detected
    #
    def receive_data data

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

    def unbind
      # TODO: detect when the remote node is down and update their 
      #       status
    end

  end

  
  # Manages a connection to our CouchDB that maintains continuous replications
  # to remote CouchDB instances. We make sure that the connection does not go
  # down while it is needed.
  #
  class ReplicationConnection
    
    attr_accessor :our_node, :our_db, :remote_node, :remote_db, :connection_inside, :name
    
    # Initiate a replication connection, by passing the local and remote
    # nodes and databases.
    #
    def initialize our_node, our_db, remote_node, remote_db, event_block
      @our_node = our_node
      @our_db = our_db
      @remote_node = remote_node
      @remote_db = remote_db
      @name = "#{our_db}->#{remote_db}"
      @keep_alive = true
      @status = "NOTRUNNING"
      @event_block = event_block
    end

    def kill
      @keep_alive = false
    end

    def start
    
      puts "Registering the replication connection for: #{@db_name}"
      node_uri = URI.parse(our_node.url)
      
      begin
        puts "Connecting to #{node_uri.host}:#{node_uri.port}"
        EM.connect node_uri.host, node_uri.port, Adhd::ReplicationNotifier, self
        @status = "RUNNING"
      rescue Exception => e
        # TODO: tag nodes as unavailable if we blow up here
        puts "PROBLEM: #{e.message}"
        throw e
      end
    end

    def event_handler data
      #puts "Run a crazy sync on db: #{@db_name}"
      #@sync_block.call(data)
      @event_block.call(:rec, data) 
    end

    def close_handler
      puts "Closed abnormally: #{reason}"
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
    

  end
  
end
