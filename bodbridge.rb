#!/usr/bin/ruby
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
    port_arg = ARGV[0]
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
    url = api_url(endpoint)
    req_method = req_method.to_s.downcase.to_sym
    uc_method = req_method.to_s.upcase

    begin
      resp = if req_method == :get then
        RestClient.get(url)
      else
        RestClient.send(req_method, url, data, content_type: :json)
      end
      result = JSON.parse(resp.body, symbolize_names:true)
    rescue RestClient::ExceptionWithResponse => err
      case err.http_code
      when 301, 302, 307
        err.response.follow_redirection
      else
        raise APIRequestError, "Failed API request #{uc_method} #{url}: received HTTP #{err.http_code}.\nRequest body: #{data || "(null)"}\nResponse body:\n#{err.response.body}"
      end
    rescue Exception => exc
      raise APIRequestError, "Failed API request #{uc_method} #{url}: caught exception #{exc.class} #{exc}.\nRequest body: #{data || "(null)"}"
    end
  end

  def dispatch_request(request_json)
    begin
      log "#{request.ip} #{request.request_method} #{request.url}: #{request_json}"
      parsed = parse_request(request_json)
      call_config = find_call(parsed[:drink])
      create_call(call_config, parsed)
      "OK"
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
      "Error handling request: #{exc.class}"
    end
  end

  def parse_request(request_json)
    begin
      raw = JSON.parse(request_json, symbolize_names:true)
    rescue JSON::ParserError
      puts request_json
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
      zone:find_zone(raw[:cabinet][:Location]),
      description:description
    }
  end

  def find_call(drink_name)
    # find an id_call_config for a requested drink name
    drink_lower = drink_name.downcase
    patterns = [
      /beverage.*#{drink_lower}$/,
      /request.*#{drink_lower}$/,
      /^#{drink_lower}.*beverage/,
      /^#{drink_lower}.*request/,
      /^#{drink_lower}$/,
      /beverage.*#{drink_lower}/,
      /request.*#{drink_lower}/,
      /#{drink_lower}.*beverage/,
      /#{drink_lower}.*request/,
      /#{drink_lower}/,
      /^drink request$/,
      /^beverage request$/,
      /^service$/,
    ]

    resp = api_request(:get, "call-config")

    patterns.each do |pattern|
      matched = resp
        .select { |cfg| cfg[:description].downcase.match(pattern) }
      log matched
      return matched.max_by { |config| config[:id] } unless matched.empty?
    end

    raise UnsupportedDrinkError, "Unable to find call for requested item: #{drink_name}"
  end

  def zonefile
    exists = File.exists?(ZONEFILE)
    recent = (Time.now - File.mtime(ZONEFILE) < ZONEFILE_EXPIRATION_TIME) rescue nil

    update_zonefile unless exists && recent

    cached = ($zonefile && Time.now - $zonefile_time < ZONEFILE_EXPIRATION_TIME) rescue nil
    cache_current = ($zonefile_time >= File.mtime(ZONEFILE)) rescue nil
    unless cached && cache_current then
      attempts = 0
      begin
        attempts += 1
        $zonefile = JSON.parse(IO.read(ZONEFILE), symbolize_names:true)
        $zonefile_time = Time.now
        log "Zonefile recached"
      rescue JSON::ParserError
        error_out "Unparseable zonefile at #{ZONEFILE}; rebuilding..."
        File.unlink(ZONEFILE)
        update_zonefile
        retry unless attempts > 1
      end
    end

    $zonefile
  end

  def update_zonefile
    text = if ZONEFILE_SCRIPT && File.executable?(ZONEFILE_SCRIPT) then
      log "Updating zonefile from script at #{ZONEFILE_SCRIPT}"
      output = `"#{ZONEFILE_SCRIPT}"`
      build_zonefile_from_api unless $?.to_i == 0
      output
    else
      build_zonefile_from_api
    end

    IO.write(ZONEFILE, text)
  end

  def build_zonefile_from_api
    log "Updating zonefile from API"
    zones = {}
    api_request(:get, "zone?all=true").each do |zone|
      zones[zone[:description]] = zone
    end

    zones.to_json
  end

  def find_zone(location)
    loc = location.to_sym
    update_zonefile unless zonefile[location.to_sym]
    unless zonefile[location.to_sym] then
      error_out "Unable to find location named #{location.to_sym}"
      return nil
    end

    zonefile[location.to_sym][:id]
  end

  def create_call(call_config, request, params={})
    id_call_config = call_config[:id]
    log "Creating call with id_call_config=#{id_call_config} (\"#{call_config[:description]}\") for drink #{request[:drink]} at location #{request[:location]} (id_zone=#{request[:zone] || "null"})"
    kai_req = {
      idCallConfig:id_call_config,
      idZone:request[:zone],
      description:request[:description]
    }

    return kai_req if params[:dryrun]
    resp = api_request(:post, "call", kai_req.to_json)
    log "Kai API accepted call with id_call_config=#{id_call_config} for drink #{request[:drink]} at location #{request[:location]} (idZone=#{request[:zone] || "null"})"
    resp
  end
end

DEFAULT_PORT = 4567
KAI_CREDENTIALS_FILE = File.expand_path("./kai_bod_api_credentials")

ZONEFILE = File.expand_path("./.kai_bod_zonefile")
ZONEFILE_SCRIPT = ENV["ZONEFILE_SCRIPT"] || File.join(File.dirname(__FILE__), "build_zonefile")
ZONEFILE_EXPIRATION_TIME = if ENV["ZONEFILE_EXPIRATION_TIME"]
  ENV["ZONEFILE_EXPIRATION_TIME"].to_f
else
  60*60 # refresh zonefile every hour by default
end

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
    port:port
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

get '/bod' do
  BANNER
end

post '/bod' do
  begin
    dispatch_request(request.body.read)
  rescue Exception => exc
    error_out "Caught exception handling request: #{exc.class} #{exc}"
    raise exc
  end
end

post '/test/parse_request' do
  parse_request(request.body.read).to_json
end

post '/test/map_request' do
  parsed = parse_request(request.body.read)
  find_call(parsed[:drink]).to_json
end

post '/test/dispatch_dryrun' do
  parsed = parse_request(request.body.read)
  call_config = find_call(parsed[:drink])
  create_call(call_config, parsed, dryrun:true).to_json
end

post '/test/find_call' do
  data = JSON.parse(request.body.read, symbolize_names:true)
  find_call(data[:drink]).to_json
end

post '/test/create_call' do
  data = JSON.parse(request.body.read, symbolize_names:true) rescue {}
  id_call_config = data[:id_call_config] || 481
  test_req = {
          drink:data[:drink]       || "Diet Pepsi",
       location:data[:location]    || "JJ0103",
           zone:data[:zone]        || find_zone("JJ0103"),
    description:data[:description] || "Test call",
  }

  create_call(id_call_config, test_req).to_json
end

