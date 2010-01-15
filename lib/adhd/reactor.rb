require 'rubygems'
require 'eventmachine'

module  Adhd

  # A notifier client that makes a long-running request to a CouchDB instance
  # on a socket and continually sends any update notifications that it
  # receives back to its @node.
  #
  module DbUpdateNotifier

    def initialize(conn_obj)
      @conn_obj = conn_obj
      @buffer = ""
      conn_obj.connection_inside = self # We tell the outer object who we are
    end

    # Makes a long-running request to a CouchDB instance's _changes URL.
    #
    def post_init
      req = "GET #{@conn_obj.base_url}/#{@conn_obj.db_name}/_changes?feed=continuous&heartbeat=5000\r\n\r\n"
      send_data req
    end

    # Shoots update notifications from CouchDB to the @conn.
    # (The events are raw strings, and it is the resposibility
    #  of the event receiver to parse the JSON)
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

  end

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
    end

    def kill clean_up_op
      @clean_up_op = clean_up_op
      connection_inside.close_connection_after_writing if connection_inside
    end

    def start
      if @status != "RUNNING"
        EM.connect @node_url, @couchdb_server_port, Adhd::DbUpdateNotifier, self
        @status = "RUNNING"
      end
    end

    def event_handler data
      @sync_block.call(data)
    end

    def unbind
      @clean_up_op.call if @clean_up_op
      @status = "NOTRUNNING"
    end

  end

end

