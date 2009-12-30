module Adhd

  # Manages a connection to our CouchDB that maintains continuous replications
  # to remote CouchDB instances. We make sure that the connection does not go
  # down while it is needed.
  #
  class ReplicationConnection

    attr_accessor :our_node, :our_db, :remote_node, :remote_db
    attr_accessor :connection_inside, :name

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
      # puts "Registering the replication connection for: #{@db_name}"
      node_uri = URI.parse(our_node.url)

      begin
        # puts "Connecting to #{node_uri.host}:#{node_uri.port}"
        EM.connect node_uri.host, node_uri.port, Adhd::Notifiers::Replication, self
        @status = "RUNNING"
      rescue Exception => e
        # TODO: tag nodes as unavailable if we blow up here
        puts "PROBLEM: #{e.message}"
        throw e
      end
    end

    def unbind
      @status = "NOTRUNNING"
      @event_block.call(:end, nil)
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

