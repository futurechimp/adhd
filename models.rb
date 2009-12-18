class Node  < CouchRest::ExtendedDocument
  NODESERVER = CouchRest.new("#{ARGV[1]}")
  NODESERVER.default_database = "#{ARGV[0]}_node_db"

  use_database NODESERVER.default_database

  property :name
  property :url
  property :is_store
  property :is_management
  property :is_directory
  property :status

  timestamps!

  view_by :name
  view_by :is_management
end

