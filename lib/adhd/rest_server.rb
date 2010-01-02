require 'eventmachine'
require 'uri'
require 'net/http'
require 'webrick'

module Adhd

  # An extremely basic HTTP server which can accept requests for storing and
  # retrieving files.  The server uses the CouchStreamerProxy to stream large
  # file attachments directly to CouchDb, which avoids writing temp files to
  # disk or massive memory growth.
  #
  # It would have been nice to use something more standard here, but Rack, for
  # example, buffers incoming files in memory until they can be dealt with
  # completely.  The lack of options which could deal with large filestreams
  # (that we could find, anyway) made us write this thing.  It's something of
  # an ugly duckling, and could use some love.
  #
  module RestServer

    attr_accessor :proxy_conn

    def initialize node_manager
      @node_manager = node_manager
      @buffer = ""
      @proxybuffer = ""
      @status = :header
    end

     #def post_init
     #  puts "-- someone connected to the echo server!"
     #end

    # The format we are expecting:
    #
    # PUT somedatabase/document/attachment?rev=123 HTTP/1.0
    # Content-Length: 245
    # Content-Type: image/jpeg
    #
    # <JPEG data>
    #
    def receive_data data

       # First we get all the headers in to find out which resource
       # we are looking for.

      if @status == :header
        @buffer += data

        if @buffer =~ /\r\n\r\n/

          # Detected end of headers
          header_data = @buffer[0...($~.begin(0))]

          @web_config = WEBrick::Config::HTTP.clone
          @web_config[:HTTPVersion] = WEBrick::HTTPVersion.new("1.0")

          # Try the webrick parser
          @req = WEBrick::HTTPRequest.new(@web_config)
          @res = WEBrick::HTTPResponse.new(@web_config)

          StringIO.open(header_data, 'rb') do |socket|
            @req.parse(socket)
          end

          # The rest of the incoming connection
          @buffer = @buffer[($~.end(0))..-1]

          # Compute the ID of the sought resource
          if @req.path =~ /\/adhd\/(.*)/
            @req.header["Filename"] = $1
            @req.header["ID"] = MD5.new($1).to_s
          else
            # TODO: return a 404 here
            send_error 404, "Not Found", "The URL does not seem to contain /adhd/filename"
            # raise "Remember to have a url of the form /adhd/<filenname>."
          end

          # Change the status once headers are found
          @status = :find_node
        else
          # Avoid DoS via buffer filling
          close_connection if @buffer.length > 1000
        end
      end

      # Now we have the headers, but maybe not the full body, and we are looking
      # for the right node in our network to handle the call.
      if @status == :find_node
              # We want to tell the remote host to wait a bit
              # This would allow us to defer the execution of the calls to find
              # the right nodes, and extract the doc.

          # TODO: We need to push all the chit-chat with the remote servers to
          #       A deferable object, or some other connection, not to block.
          #       Right now we are blocking and it sucks.

        # Now get or write the document associated with this file

        if @req.request_method == "GET"

          @our_doc = @node_manager.srdb.get_doc_directly(@req.header["ID"])

          # TODO: handle errors if file does not exist
          if @our_doc[:ok]
            @status == :get
              handle_get
            else
              send_error 500, "Internal Server Error", @our_doc[:reason]
            end
          end

          if @req.request_method == "PUT"
            # Define a Doc with the data so far
            @our_doc = StoredFile.new

            @our_doc._id = @req.header["ID"]
            @our_doc.internal_id = @req.header["ID"]
            @our_doc.size_bytes = @req.content_length
            @our_doc.filename = @req.header["Filename"]
            @our_doc.mime_type = @req.content_type

            # Write to the right node
            @our_doc = @node_manager.srdb.write_doc_directly(@our_doc)

            # TODO: if an error is returned here, we cannot execute the query
            if @our_doc[:ok]
              @status = :put
              handle_put
            else
              send_error 410, "Conflict", @our_doc[:reason]
            end
          end
        end
      end

    def send_error code, message, explanation
      send_data "HTTP/1.0 #{code} #{message}\r\n"
      send_data "Content-Length: #{explanation.length}\r\n"
      send_data "\r\n"
      send_data explanation
      close_connection_after_writing
    end

    def handle_get
      # We need to connect to the right server and build a header
      server_uri = URI.parse(@our_doc[:db].server.uri)
      server_addr = server_uri.host
      server_port = server_uri.port

      docid = @our_doc[:doc]._id
      dbname = @our_doc[:db].name
      request = "GET /#{dbname}/#{docid}/#{@our_doc[:doc].filename} HTTP/1.0\r\n\r\n"
      puts "Connect to #{server_addr} port #{server_port}"
      puts "#{request}"
      conn = EM::connect server_addr, server_port, CouchStreamerProxy, self, request
    end

    # Our connection to the CouchDB has just been torn down
    #
    def proxy_unbind
      close_connection_after_writing
    end

    # Handles data ariving from the upstream server to the client
    # First it parses the headers, and then it streams the data through
    # using the event machine proxying mechanism.
    #
    def proxy_receive_data data
      @proxystatus = :headers if !@proxystatus
      
      if @proxystatus == :headers
        # First gather the headers
        @proxybuffer += data
        if @proxybuffer =~ /\r\n\r\n/

          # Detected end of headers
          header_data = @proxybuffer[0...($~.begin(0))]
          @proxybuffer = @proxybuffer[($~.end(0))..-1]

          # Try the webrick parser
          headers = {}
          header_lines = header_data.split(/[\r\n]+/)
          status = header_lines[0]
          header_lines[1..-1].each do |line|
            h = line.split(/:\s*/, 2)
            headers[h[0]] = h[1]
          end
          
          # The rest of the incoming connection                    
          @proxystatus = :stream
        end
      end
      
      if @proxystatus == :stream
        send_data header_lines[0] + "\r\n"
        send_data "Content-Type: " + headers['Content-Type'] + "\r\n"
        send_data "Content-Length: " + headers['Content-Length'] + "\r\n"
        send_data "\r\n"
        send_data @proxybuffer

        # Any further data is piped through         
        EM::enable_proxy proxy_conn, self, 1024*10
      end
    end

    def handle_put
      # We need to connect to the right server and build a header
      server_uri = URI.parse(@our_doc[:db].server.uri)
      server_addr = server_uri.host
      server_port = server_uri.port

      docid = @our_doc[:doc]._id
      dbname = @our_doc[:db].name
      request = "PUT /#{dbname}/#{docid}/#{@our_doc[:doc].filename}?rev=#{@our_doc[:doc]["_rev"]} HTTP/1.0\r\n"
      request += "Content-Type: #{@our_doc[:doc].mime_type}\r\n"
      request += "Content-Length: #{@our_doc[:doc].size_bytes}\r\n"
      request += "\r\n"
      request += @buffer
      conn = EM::connect server_addr, server_port, CouchStreamerProxy, self, request
      EM::enable_proxy self, proxy_conn, 1024 * 10
    end

    def unbind
      # puts "-- someone disconnected from the echo server!"
    end
  end

  # This implements the connection that proxies an incoming file to a
  # CouchDB instance, as an attachment.  We stream incoming files so that
  # we don't need to buffer them in memory (which would be psychotic for large
  # files) or write them to disk as temp storage (eating up disk space and
  # causing lag).
  #
  module CouchStreamerProxy

    def initialize our_client_conn, init_request
      @our_client_conn = our_client_conn
      @init_request = init_request
      our_client_conn.proxy_conn = self
    end

    # We have opened a connection to the CouchDB server, so now it is time
    # to send the initial Couch request, using HTTP 1.0.
    #
    def post_init
       send_data @init_request
    end

    def receive_data data
      @our_client_conn.proxy_receive_data data
    end

    def unbind
      @our_client_conn.proxy_unbind
    end

  end
end

