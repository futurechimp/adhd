require 'rubygems'
require 'eventmachine'

module  Adhd

  # This module gets mixed into the EventMachine reactor loop, and sends events
  # to our Adhd::Node which is hanging around waiting for shit to happen.
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

  # A reactor that makes a long-running request to a CouchDB instance (using
  # Comet technology) and continually sends any update notifications that it
  # gets back to its @node.
  #
  module DbUpdateReactor

    def initialize(node)
      puts "Db update reactor start..."
      @node = node
    end

    # Makes a long-running request to a CouchDB instance's _changes URL.
    #
    def post_init
      send_data "GET http://192.168.1.104:5984/bar_node_db/_changes?feed=continuous&heartbeat=5000\r\n\r\n"
    end

    # Shoots update notifications from CouchDB to the @node.
    #
    def receive_data data
      @node.event_handler(data)
    end

  end
end

