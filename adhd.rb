require 'rubygems'
require 'sinatra'
require 'couchrest'
require 'erb'
require 'ruby-debug'
require File.dirname(__FILE__) + '/models'

def get_node_db(node)
  server = CouchRest.new("#{node.url}")
  server.database!("#{node.name}_node_db")
end

node_name = ARGV[0]
node_url = ARGV[1]
buddy_server_url = ARGV[2] 
if buddy_server_url == "NONE"
  buddy_server_url = nil
end

if ! (buddy_server_url == "None")
  buddy_db =  ARGV[3]
end

puts "Buddy is #{buddy_server_url}/#{buddy_db}" 

ournode = CouchRest.new("#{node_url}")

puts "Build or open DB #{node_url}/#{node_name}_node_db"
node_db = ournode.database!("#{node_url}/#{node_name}_node_db")

# sync the db with our buddy
if buddy_server_url && buddy_db
  puts "Replicate node_db from #{buddy_server_url}/#{buddy_db}_node_db"
  buddynode = CouchRest.new("#{buddy_server_url}")
  buddy_db_dd = buddynode.database!("#{buddy_db}_node_db")
  puts "Trying to replicate from #{node_db.uri} to #{buddy_db_dd.uri}"
  node_db.replicate_from(buddy_db_dd)
end

node = Node.by_name(:key => node_name).first
node = Node.new if node.nil?

node.name = node_name
node.url = node_url
node.save

# Check if we are the very first node in the database
all_nodes = Node.by_name()
if all_nodes.length == 1
  # We are the first node in the system, so become admin
  puts "Setup #{node.name} as management node"
  node.is_management = 3
  node.save
end

# We check if we are the first node. If we are the first node, we set ourself up
# as the management node. If not, we find out where the management node is and
# we replicate to the administrative node.
if !node.is_management && management_node = Node.by_is_management.last
  puts "Push to management node #{management_node.url}/#{management_node.name}..." 
  management_node_db = get_node_db(management_node)
  node_db.replicate_to(management_node_db)
end

