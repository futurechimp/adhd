# A fake NodeDb subclass which we only use in tests.  It saves us from having
# to create thousands of real CouchDb databases on disk, which would be slow
# and suck.
#
class FakeAssNodeDb < NodeDB

  # Returns a list of FakeAssNode management nodes.
  #
  def find_management_nodes
    @nodes.select {|n| n.is_management && n.is_management > 0}
  end

  # Sets up the fake list of nodes so we can access them later when testing.
  #
  def set_nodes nodes
    @nodes = nodes
  end

end

