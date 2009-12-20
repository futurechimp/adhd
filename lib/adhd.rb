require 'rubygems'
require 'sinatra'
require 'couchrest'
require 'erb'
require 'ruby-debug'
require File.dirname(__FILE__) + '/adhd/models/node_doc'
require File.dirname(__FILE__) + '/adhd/models/shard_range'
require File.dirname(__FILE__) + '/adhd/models/content_shard'

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
node.status = "RUNNING"
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
ndb = NodeDB.new(node)

# Lets build a nice ShardDB
srdb = ShardRangeDB.new(ndb)

# If there are no shards make a few, if we are managers
#puts "Create new ranges?"
#puts "How many shards: #{ShardRange.by_range_start.length}"
#puts "in #{ShardRange::SHARDSERVER.default_database}"
if ShardRange.by_range_start.length == 0 && node.is_management
  puts "Creating new ranges"
  srdb.build_shards(100)
end

# Polulate the shards with some nodes at random
node_names = []
all_nodes.each do |anode|
  node_names << anode.name
end

# Allows us to shuffle arrays
class Array
  def shuffle!
    size.downto(1) { |n| push delete_at(rand(n)) }
    self
  end
end

ShardRange.by_range_start.each do |s|
  if !s.node_list or s.node_list.length == 0
    node_names.shuffle!
    s.node_list = node_names[0..2]
    s.master_node = node_names[0]
    s.save
  end

end

contentdbs = srdb.get_content_shards

# Print all the shards we are in charge of
shard_name = []
contentdbs.each do |content_shard_db|
  shard_name << content_shard_db.this_shard.shard_db_name
end
puts "Storing #{shard_name}"

# Sync all the node databases
ndb.sync # SYNC
srdb.sync # SYNC

contentdbs.each do |content_shard_db|
  content_shard_db.sync
end

get "/" do
  @all_nodes = Node.by_name
  erb :index
end

get "/sync" do
  # Sync the node database
  ndb.sync
  # Sync the shard database
  srdb.sync

  contentdbs.each do |content_shard_db|
    content_shard_db.sync
  end
end

