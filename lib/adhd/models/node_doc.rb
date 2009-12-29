# An adhd management node containing information about the cluster.
#
# TODO: rename this file to "node.rb" instead of  "node_doc.rb"
#
# TODO: ditch the "get_" stuff, we're not writing C# here.
#

require File.dirname(__FILE__) + '/replication_connection'

# We need to centralise the management of replication
# connections to make sure that we do not call one when it is not necessary
#
# A replication manager keeps track of how often we have been replicating
# a db and ensure replications do not happen too often.
class ReplicationManager

  def initialize interval
    @interval = interval
    @schedule = {}    
    @active = false
  end
  
  def add_replication conn
     
    if @schedule.has_key? conn.name
      return
    else 
      @schedule[conn.name] = conn
      
      if !@active
        @active = true
        EM::add_timer(@interval) { run_replications }
      end    
    end        
  end
  
  def run_replications
      # Add fresh schedule
      old_shedule = @schedule
      @schedule = {}
      @active = false
      
      old_shedule.each_value do |conn|
        conn.start
      end
  end
end

class Node  < CouchRest::ExtendedDocument
  unique_id :name

  property :name
  property :url
  property :is_store
  property :is_management
  property :is_directory
  property :status

  timestamps!

  view_by :name
  view_by :is_management

  def get_node_db
    server = CouchRest.new("#{url}")
    db = server.database!("#{name}_node_db")
  end

  def get_shard_db
    server = CouchRest.new("#{url}")
    db = server.database!("#{name}_shard_db")
  end

  def get_content_db(shard_db_name)
    server = CouchRest.new("#{url}")
    db = server.database!("#{name}_#{shard_db_name}_content_db")
  end

  # Replicating databases and marking nodes as unavailable
  # In the future we should hook these into a "replication manager"
  # for databases. The manager should set up continuous replication across
  # databases, and only do a replication after some time lapses.

  def replicate_to(local_db, other_node, remote_db)
    replicate_to_or_from_async(local_db, other_node, remote_db, true)
  end

  def replicate_from(local_db, other_node, remote_db)
    replicate_to_or_from_async(local_db, other_node, remote_db, false)
  end

  private

  @@replication_manager = ReplicationManager.new(2)


  # Replicates to or from a management node database.  The direction of
  # replication is controlled by a boolean property.
  #
  # Returns true if replication succeeds, false if not.
  #
  def replicate_to_or_from_async(local_db, other_node, remote_db, to = true)
    # Do not try to contact unavailable nodes
    return false if other_node.status == "UNAVAILABLE"
    # No point replicating to ourselves
    return false if (name == other_node.name)

    # Define a call back
    endconn = Proc.new do |ev, data|       
        if ev == :rec
          #puts "DID Sync #{local_db.name} from to #{other_node.name}: #{data}"
        else
          #puts "END Sync #{local_db.name} from to #{other_node.name}"
        end
    end

    begin
      # Replicate to other node is possible
      if to
        if EM::reactor_running?()
          conn = Adhd::ReplicationConnection.new other_node, remote_db, 
                                                  self, local_db, endconn 
          @@replication_manager.add_replication conn
        else
          remote_db.replicate_from(local_db)
        end  
                
      else
        if EM::reactor_running?()
          conn = Adhd::ReplicationConnection.new self, local_db, other_node, 
                                                 remote_db, endconn
          @@replication_manager.add_replication conn
        else
          local_db.replicate_from(remote_db)
        end
      end
      return true
    rescue Exception => e
      # Other node turns out to be unavailable
      other_node.status = "UNAVAILABLE"
      other_node.save
      return false
    end

  end



end

