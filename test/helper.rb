require 'rubygems'
require 'sinatra'
require 'rack/test'
require 'base64'
set :environment, :test
set :run, false
set :raise_errors, true
set :logging, false
require File.dirname(__FILE__) + '/../adhd'


module TestHelper

  def app
    # change to your app class if using the 'classy' style
    Sinatra::Application.new
  end

  def body
    last_response.body
  end

  def status
    last_response.status
  end

  include Rack::Test::Methods

end


require 'test/unit'
require 'shoulda'


Test::Unit::TestCase.send(:include, TestHelper)

