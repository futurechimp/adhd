require 'rubygems'
require 'test/unit'
require 'shoulda'

class TestAdhd <  Test::Unit::TestCase

  context "An adhd node" do
    context "at startup" do

      setup do
        # TODO: this is total shit and needs to come out.  We could read a
        # config file for tests instead of hardcoding all this crap, and
        # probably localhost would do us just fine.
        assert_nothing_raised do
          NODESERVER = CouchRest.new("http://192.168.1.93:5984")
          NODESERVER.default_database = "node_db"
          @node_db = CouchRest::Database.new(NODESERVER, "node_db")
        end
      end

      should_eventually "create a view for name" do
        # @node_db.get("_design/node")
      end

      context "if given another node url" do
        should_eventually "replicate the remote node database" do
        end
      end

      should_eventually "have a node descriptor in its database for itself" do
      end
    end
  end

end

