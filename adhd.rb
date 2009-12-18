require 'rubygems'
require 'sinatra'
require 'couchrest'
require 'erb'
require 'ruby-debug'
require File.dirname(__FILE__) + '/models'

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
  buddy_db = CouchRest::Database.new(buddy_server, buddy_db)
  node_db.replicate_from(buddy_db)
end

node = Node.by_name(:key => node_name).first
node = Node.new if node.nil?

node.name = node_name
node.url = node_url
node.save

# We check if we are the first node. If we are the first node, we set ourself up
# as the management node. If not, we find out where the management node is and
# we replicate to the administrative node.
if management_node = Node.by_is_management.last
  management_node_server = CouchRest.new(management_node.url)
  management_node_db = CouchRest::Database.new(management_node_server, management_node.name + "_node_db")
  node_db.replicate_to(management_node_db)
else
  node.is_management = 3
  node.save
end

