require 'sinatra'

set  :run => false
set  :environment => :production

disable :reload

run Sinatra::Application

require File.dirname(__FILE__) + '/adhd'

