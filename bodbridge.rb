#!/usr/bin/ruby
#
# DESCRIPTION
# Bridge between IGT Beverage on Demand (BOD) and Acres 4 Kai.
#
# Listens for HTTP POST from BOD. BOD must be configured
# to send this POST to IP address for machine running bodbridge
# on port 4567.
#
# Sends Kai API request to create call based on drink order.
#
#
# INSTALLATION
# This script must be run on the same VM as your Kai server.
#
# 1. Install ruby and gems
# Install Ruby (tested with version 2.2), and the following gems:
#   sinatra
#   rest-client
# eg. `sudo gem install sinatra rest-client`
# 
# 2. Configure API credentials
# Set up an API user in Kai. Place the sitename, username and password each on
# their own line in a file called "./kai_bod_api_credentials" relative to the
# working directory when running this script, eg.
# 
# ```
# rivervalleycasino
# bodapiuser
# SecretPassword123
# ```
#
# 3. Configure beverage-on-demand
# Configure beverage-on-demand to provide HTTP POSTs to the VM's
# IP address with the configured port number, e.g.
#  http://10.2.3.4:4567/bod
#
# It is highly recommended to use /bod as the endpoint for forward
# compatibility. This service will accept any endpoint, however.
#
# 4. Configure calls in Kai
# Create calls matching beverage menu items as desired. See
# "CALL CONFIGURATION" section below.
#
# 5. Install script
# Install this script on the VM, and set up whatever monitoring is
# desired. The supplied `bodbridge.service` script is intended for use
# on systems running systemd.
#
# The site name must be supplied as the first command line argument, eg.
# bodbridge.rb tablemountaincasino
#
# Note that bodbridge writes helpful debug output to STDOUT, and error
# messages to STDERR.
#
#
# PORT CONFIGURATION
# Default HTTP port for BOD postbacks: 4567
# 
# The port number can be optionally specified as the first command line
# argument, e.g.
#  ./bodbridge.rb 1234
# will cause bodbridge to listen for HTTP POSTs on TCP 1234.
#
#
# CALL CONFIGURATION
# bodbridge will use the name of the drink requested to create an
# appropriate call when possible. It will look for calls with the following
# names. It will use the first matching call it finds that is configured.
#  (* indicates wildcard, matches are case insensitive)
#
#  - Beverage*coffee
#  - Request*coffee
#  - Coffee*request
#  - Coffee*beverage
#  - Coffee
#  - Beverage request
#  - Drink request
#  - Service
#
# If no matching calls are found, no call is created.
# If multiple matching calls exist, the one whose name matches a pattern
# listed highest above will be used. If multiple calls exist for the
# same pattern, the one with the highest id_call_config is used.
#
#
# MULTIPLE ITEMS IN ORDER
# If an order contains multiple items, only the first item is used
# in selecting an appropriate id_call_config. All items (including the
# first and subsequent items) are listed in the description field
# supplied to the Kai API.
#
#
# TROUBLESHOOTING
# Problem: UnsupportedDrinkError exceptions
# Resolution: Ensure that Kai call configuration has at least one call
# enabled that supports a beverage with the indicated name. See "CALL CONFIGURATION"
# section for more information.
#
# Problem: APIRequestError exceptions
# Resolution: Ensure that Kai API user credentials are set up with Kai,
# and correctly specifeid in the ./kai_bod_api_credentials file. Also check
# that Kai API server is reachable from the machine running bodbridge as
# https://username:password@sitename.kailabor.com/api/v3
#
# Problem: UnsupportedRequestFormatError exceptions
# Resolution: Request format received from BOD is not understood by this script.
# Ensure that bodbridge is receiving callbacks from supported version of BOD.
#
#
# AUTHOR
# Completed on contract for Acres Bonusing.
#
# Jonas Acres
# jonas@acrescrypto.com
# 702-481-4146
#

require 'sinatra'
require 'rest-client'
require 'json'

class UnsupportedRequestFormatError < StandardError
end

class UnsupportedDrinkError < StandardError
end

class APIRequestError < StandardError
end

def enforce_command_line!
  die_with_usage!("Too many arguments") if ARGV.count > 1
  if ARGV.count == 1 then
    port_arg = ARGV[1]
    die_with_usage!("http_port_num must be integer") if port_arg.match(/^\d+$/).nil?
    die_with_usage!("http_port_num must be positive") if port_arg.to_i <= 0
    die_with_usage!("http_port_num must be less than 65536") if port_arg.to_i >= 65536
  end
end

def die_with_usage!(msg=nil)
  STDERR.puts(msg) if msg
  puts BANNER
  puts "Usage: #{__FILE__} [http_port_num]"
  puts "    http_port_num: Default 4567. HTTP port number to listen for beverage-on-demand POST requests."
  exit 1
end

def parse_api_credentials
  path = KAI_CREDENTIALS_FILE
  demand_api_credentials!("API credentials file not found: #{path}") unless File.exists?(path)
  sitename, username, password = IO.read(path).split("\n")
  demand_api_credentials!("Must supply sitename in Kai API credentials file") unless sitename
  demand_api_credentials!("Must supply username in Kai API credentials file") unless username
  demand_api_credentials!("Must supply password in Kai API credentials file") unless password
  { sitename:sitename, username:username, password:password }
end

def demand_api_credentials!(msg=nil)
  STDERR.puts(msg) if msg
  puts "Error parsing Kai credentials file at #{KAI_CREDENTIALS_FILE}"
  puts "API credentials file format: sitename, username and password each on separate line, e.g."
  puts "kaisite"
  puts "someuser"
  puts "somepassword123"
  exit 1
end

def error_out(msg)
  timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
  STDERR.puts "#{timestamp} E: #{msg}"
end

def log(msg)
  timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
  puts "#{timestamp} I: #{msg}"
end

helpers do
  def api_url(endpoint)
    kai = $config[:kai]
    url = "https://#{kai[:username]}:#{kai[:password]}@#{kai[:sitename]}.kailabor.com/api/v3/#{endpoint}"
  end

  def api_request(req_method, endpoint, data=nil)
    args = data.nil? ? {} : {data:data.to_json, content_type: :json}
    url = api_url(endpoint)
    req_method = req_method.to_s.downcase.to_sym
    uc_method = req_method.to_s.upcase

    begin
      resp = RestClient.send(req_method, url, args)
      result = JSON.parse(resp.body, symbolize_names:true)
    rescue RestClient::ExceptionWithResponse => err
      case err.http_code
      when 301, 302, 307
        err.response.follow_redirection
      else
        raise APIRequestError, "Failed API request #{uc_method} #{url}: received HTTP #{err.http_code}.\nRequest body: #{args[:data] || "(null)"}\nResponse body:\n#{err.response.body}"
      end
    rescue Exception => exc
      raise APIRequestError, "Failed API request #{uc_method} #{url}: caught exception #{exc.class} #{exc}.\nRequest body: #{args[:data] || "(null)"}"
    end
  end

  def map_request(request_json)
    begin
      request = parse_request(request_json)
      id_call_config = find_call(request[:drink])
      create_call(id_call_config, request)
    rescue Exception => exc
      bt = exc.backtrace.map { |line| "    #{line.to_s}" }.join("\n")
      lines = []
      lines << "Caught exception handling BOD request: #{exc.class} #{exc}"
      lines << "Request: #{request.request_method} #{request.url}"
      lines << "Requestor IP: #{request.ip}"
      lines << "Body: #{request.content_length} bytes, media type #{request.media_type}"
      lines << request_json
      lines << "Backtrace:\n#{bt}"
      error_out lines.join("\n")
    end
  end

  def parse_request(request_json)
    begin
      raw = JSON.parse(request_json, symbolize_names:true)
    rescue JSON::ParserError
      raise UnsupportedRequestFormatError, "Unable to parse request as JSON"
    end

    (raw.is_a?(Hash) &&
     raw[:order].is_a?(Hash) &&
     raw[:order][:cart].is_a?(Array)
    ) or raise UnsupportedRequestFormatError, "Unable to interpret request"

    item = raw[:order][:cart].first or raise UnsupportedRequestFormatError, "No drinks included in request"
    item[:name] or raise UnsupportedRequestFormatError, "Requested drink did not include name field"
    raw[:cabinet] && raw[:cabinet][:Location] or raise UnsupportedRequestFormatError, "Request did not include cabinet location"

    description = "Beverage request: " + raw[:order][:cart].map do |ii|
      ii[:name] + if ii[:modified] && !ii[:modified].empty? then
        " (with " + ii[:modified].map { |mm| mm[:name] }.join(", ") + ")"
      else
        ""
      end
    end.join(", ")

    request = {
      drink:raw[:order][:cart].first[:name],
      location:raw[:cabinet][:Location],
      description:description
    }
  end

  def find_call(drink_name)
    # find an id_call_config for a requested drink name
    patterns = [
      /beverage.*#{drink_name}/,
      /request.*#{drink_name}/,
      /#{drink_name}.*request/,
      /#{drink_name}.*beverage/,
      /#{drink_name}/,
      /beverage request/,
      /drink request/,
      /service/,
    ]

    resp = api_request(:get, "call-config")

    patterns.each do |pattern|
      matched_id = resp[:call_config]
        .select { |cfg| cfg[:description].downcase.match(pattern) }
        .map { |config| config[:id_call_config] }
        .max
      return matched_id unless matched_id.nil?
    end

    raise UnsupportedDrinkError, "Unable to find call for requested item: #{drink_name}"
  end

  def create_call(id_call_config, request)
    log "Creating call with id_call_config=#{id_call_config} for drink #{request[:drink]} at location #{request[:location]}"
    kai_req = {
      idCallConfig:id_call_config,
      location:request[:location],
      description:request[:description]
    }

    resp = api_request(:post, "call", kai_req)
    log "Kai API accepted call with id_call_config=#{id_call_config} for drink #{request[:drink]} at location #{request[:location]}"
    resp
  end
end

DEFAULT_PORT = 4567
KAI_CREDENTIALS_FILE = File.expand_path("./kai_bod_api_credentials")

enforce_command_line!
port = ARGV.count >= 1 ? ARGV[0].to_i : DEFAULT_PORT
api_creds = parse_api_credentials

$config = {
  kai:{
    sitename:api_creds[:sitename],
    username:api_creds[:username],
    password:api_creds[:password],
  },

  http:{
    port:4567
  },

  version:"2019-04-30"
}

BANNER = "IGT Beverage-on-Demand -> Acres 4 Kai API bridge #{$config[:version]}"

log BANNER
log "Listening for Beverage-on-Demand HTTP POSTs on TCP port: #{$config[:http][:port]}"
log "Configured API user: #{api_creds[:username]} @ #{api_creds[:sitename]}"

set :port, $config[:http][:port]
set :bind, '0.0.0.0'

get '/' do
  BANNER
end

post '/bod' do
  begin
    request_json = request.body.read
    log "#{request.ip} #{request.request_method} #{request.url}: #{request_json}"
    map_request(request_json)
  rescue Exception => exc
    error_out "Caught exception handling request: #{exc.class} #{exc}"
    raise exc
  end
end

post '/test/parse' do
  parse_request(request.body.read).to_json
end

post '/test/find_call' do
  data = JSON.parse(request.body.read, symbolize_names:true)
  { id_call_config:find_call(data[:drink]) }.to_json
end

post '/test/create_call' do
  data = JSON.parse(request.body.read, symbolize_names:true)
  id_call_config = data[:id_call_config] || 481
  test_req = {
          drink:data[:drink]       || "Diet Pepsi",
       location:data[:location]    || "JJ0103",
    description:data[:description] || "Test call",
  }

  create_call(id_call_config, test_req).to_json
end

