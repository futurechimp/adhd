# Maps ContentDocs to ShardDBs based on the filename of a file.
#
# Given a filename, the ShardRange can figure out which shard database
# should store that file for insertion or retrieval. The file's ID will fall
# between the <tt>range_start</tt> and a <tt>range_end</tt>).
#
class ShardRange < CouchRest::ExtendedDocument

  unique_id :shard_db_name

  property :range_start
  property :range_end
  property :node_list
  property :master_node
  property :shard_db_name

  # Retrieve a ShardRange based on its range_start property.
  #
  view_by :range_start

  # The CouchDB view "node" - given a node returns the shards watched
  #
  view_by :node,
          :map =>
          "function(doc) {
          if (doc['couchrest-type'] == 'ShardRange' && doc.node_list) {
            doc.node_list.forEach(function(node){
              emit(node, 1);
            });
          }
        }"

  # Returns all nodes, with the master node being first
  #
  def get_nodes
    all_nodes = node_list.clone
    all_nodes.delete(master_node)
    all_nodes = [master_node] + all_nodes
    all_nodes
  end

end

