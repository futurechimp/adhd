require 'rubygems'
require 'sinatra'
require 'couchrest'
require 'erb'
require 'ruby-debug'
require File.dirname(__FILE__) + '/adhd/models'

# Start the server for now by cd'ing into the /lib directory and running the
# following command:
#
# (first node):
# ruby adhd.rb <node_name> <couchdb_server_url>
#
# (second or later node)
# ruby adhd.rb <node_name> <couchdb_server_url> <management_node_url> <management_node_db> -p <port_number>
#
# <node_name> is just a string, e.g. "foo".
# <couchdb_server_url>: the url (including port) for this node's couchdb server
#   instance, e.g, http://192.168.1.104:5984
# <management_node_url>: the url of the management node where this node should
#   initially replicate from, e.g. http://192.168.1.104:5984
# <management_node_db>: the couchdb management node database, e.g. "bar_node_db"
# <port_number>: a port number to run on. If you're running more than one node locally
#   for development purposes you'll need to pick a non-default port higher than 1024.


node_name = ARGV[0]
node_url = ARGV[1]
buddy_server_url = ARGV[2]
buddy_db =  ARGV[3]

NODESERVER = CouchRest.new("#{node_url}")
NODESERVER.default_database = "#{node_name}_node_db"
node_db = CouchRest::Database.new(NODESERVER, "#{node_name}_node_db")

# sync the db with our buddy
if buddy_server_url && buddy_db
  buddy_server = CouchRest.new("#{buddy_server_url}")
  buddy_db = CouchRest::Database.new(buddy_server, buddy_db + "_node_db")
  node_db.replicate_from(buddy_db)
end

# Retrieve our own node by our name
# If there are other nodes with the name kill their records!
node_candidates = Node.by_name(:key => node_name)
node = node_candidates.pop
node = Node.new if node.nil?
node_candidates.each do |other_me|
  other_me.destroy # destroy other records
end

# Update our very own record
node.name = node_name
node.url = node_url
node.save

# We check if we are the first node. If we are the first node, we set ourself up
# as the management node. 
all_nodes = Node.by_name()
if all_nodes.length == 1
  # puts "Setup #{node.name} as management node"
  node.is_management = 3
  node.save
end

# Lets build a nice NodeDB
ndb = NodeDB.new
ndb.local_node_db = node_db
ndb.our_node = node

ndb.sync # SYNC

get "/admin" do
  all_nodes = Node.by_name()
  s = '<html><body>'
  all_nodes.each do |n|
    s += "#{n.name} | #{n.url} | #{n.is_management}<br/>"
  end
  s += '</body></html>'
end


