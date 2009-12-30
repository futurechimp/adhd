require File.dirname(__FILE__) + '/replication_connection'

module Adhd

  # We need to centralise the management of replication
  # connections to make sure that we do not call one when it is not necessary
  #
  # The replication manager keeps track of how often we have been replicating
  # a CouchDB and ensure replications do not happen too often. Internally the
  # manager keeps track of pending replication connections, and activates /
  # executes them within a period of time set as an interval. If replication
  # between two resources is requested multiple times it is only perfomed once
  # during the interval.
  #
  class ReplicationManager

    def initialize interval
      @interval = interval

      # A hash of replication connections by name, pending execution
      @schedule = {}
      @active = false
    end

    # Add a replication connection to the replication shedule
    # If the same replication is already scheduled it will only happen once.
    #
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

    # Run all the replications requested, and start a new schedule
    #
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

end

