require 'eventmachine'
require 'uri'
require 'net/http'
require 'webrick'

 module ProxyToServer
  # This implements the connection that proxies an incoming file to to the
  # respective CouchDB instance, as an attachment.

  def initialize our_client_conn, init_request
    @our_client_conn = our_client_conn
    @init_request = init_request
    our_client_conn.proxy_conn = self
  end

  def post_init
     # We have opened a connection to the DB server, so now it is time
     # to send the initial Couch request, using HTTP 1.0.
     send_data @init_request
  end

  def receive_data data
    @our_client_conn.proxy_receive_data data
  end

  def unbind
    @our_client_conn.proxy_unbind
  end

 end

 module AdhdRESTServer
  attr_accessor :proxy_conn

  def initialize node_manager
    @node_manager = node_manager
    @buffer = ""
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

   def receive_data data

     # First we get all the headers in to find out which resource
     # we are looking for.

     if @status == :header
       @buffer += data

       if data =~ /\r\n\r\n/

        # Detected end of headers
        header_data = @buffer[0...($~.begin(0))]

       @web_config = WEBrick::Config::HTTP.clone
       @web_config[:HTTPVersion] = WEBrick::HTTPVersion.new("1.0")

        # Try the webrick parser
        @req = WEBrick::HTTPRequest.new(@web_config)
        @res = WEBrick::HTTPResponse.new(@web_config)


        puts @res.to_s

        StringIO.open(header_data, 'rb') do |socket|
          @req.parse(socket)
        end

        # The rest of the incomming connection
        @buffer = @buffer[($~.end(0))..-1]

        # Compute the ID of the sought resource
        if @req.path =~ /\/adhd\/(.*)/
          @req.header["Filename"] = $1
          @req.header["ID"] = MD5.new($1).to_s
        else
          # TODO: return a 404 here
          raise "Remember to have a url of the form /adhd/<filenname>."
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
        pause # We want to tell the remote host to wait a bit
              # This would allow us to defer the execution of the calls to find
              # the right nodes, and extract the doc.

        # TODO: We need to push all the chit-chat with the remote servers to
        #       A deferable object, or some other connection, not to block.
        #       Right now we are blocking and it sucks.

        # Now get or write the document associated with this file
        
        # EM.defer {
        if @req.request_method == "GET"

          @our_doc = @node_manager.srdb.get_doc_directly(@req.header["ID"])

          # TODO: handle erros if file does not exist
          if @our_doc[:ok]
            @status == :get
            handle_get
          else
            send_data "Problem"
            close_connection
          end
        end
        
        if @req.request_method == "PUT"
          # Define a Doc with the data so far
          @our_doc = ContentDoc.new

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
            send_data "Problem"
            close_connection
          end
        end
        # }

        # Now send the reply as an HTTP1.0 reponse

        # HTTP/1.0 200 OK
        # Date: Fri, 08 Aug 2003 08:12:31 GMT
        # Server: Apache/1.3.27 (Unix)
        # MIME-version: 1.0
        # Last-Modified: Fri, 01 Aug 2003 12:45:26 GMT
        # Content-Type: text/html
        # Content-Length: 2345
        # ** a blank line *
        # <HTML> ...



      # response = @our_doc.to_s
      #
      # send_data "HTTP/1.0 200 OK\r\n"
      # send_data "Content-Type: text/plain\r\n"
      # send_data "Content-Length: #{response.length}\r\n"
      # send_data "\r\n"
      # send_data response
      #
      # # Close the connection
      # close_connection_after_writing

     end

     # We have the header and the node, and now we execute the request
     if @status == :execute_request

     end

   end

  def handle_get
    resume
    # We need to connect to the right server and build a header
    server_uri = URI.parse(@our_doc[:db].server.uri)
    server_addr = server_uri.host
    server_port = server_uri.port

    docid = @our_doc[:doc]._id
    dbname = @our_doc[:db].name
    request = "GET /#{dbname}/#{docid}/#{@our_doc[:doc].filename} HTTP/1.0\r\n\r\n"
    #send_data request
    #close_connection_after_writing
    # puts "Connect to #{server_addr} port #{server_port}"
    conn = EM::connect server_addr, server_port, ProxyToServer, self, request
    EM::enable_proxy proxy_conn, self, 1024*10
  end

  def proxy_unbind
    # Our connection to the CouchDB has just been torn down
    close_connection_after_writing
  end

  def proxy_receive_data data
    # Response to a PUT request only
    send_data data
  end


  def handle_put
    resume

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
    #send_data request
    #close_connection_after_writing
    # puts "Connect to #{server_addr} port #{server_port}"
    conn = EM::connect server_addr, server_port, ProxyToServer, self, request
    EM::enable_proxy self, proxy_conn, 1024 * 10
  end

   def unbind
     # puts "-- someone disconnected from the echo server!"
   end
 end

