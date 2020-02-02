require './auth'
require './bot'

# initialize app and create the API (bot) and Auth objects
run Rack::Cascade.new [API, Auth]
