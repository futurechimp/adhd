module  Adhd
  module Replication
    module Notifier

      def initialize(conn_obj)
        @conn_obj = conn_obj
        @buffer = ""
        conn_obj.connection_inside = self # We tell the outer object who we are
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
      # Buffers data until a JSON object is detected.
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

      # TODO: detect when the remote node is down and update their status.
      #
      def unbind
        @conn_obj.unbind
      end

    end
  end
end

