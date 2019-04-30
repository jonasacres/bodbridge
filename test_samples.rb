#!/usr/bin/ruby

require 'colorize'
require 'rest-client'

def usage!
  valid_mode_str = $valid_modes.map { |mm| mm.to_s }.join(", ")
  STDERR.puts "Missing or invalid mode. Valid modes: #{valid_mode_str}"
  exit 1
end

def endpoint_for_mode(mode)
  endpoint = case mode.to_sym
  when :parse
    "test/parse_request"
  when :map
    "test/map_request"
  when :dryrun
    "test/dispatch_dryrun"
  when :dispatch
    "bod"
  else
    nil
  end
end

sample_dir = File.join(File.dirname(__FILE__), "samples")
samples = Dir.glob(File.join(sample_dir, "**/*.json"))
$valid_modes = [
  :parse,    # test parsing of each sample request
  :map,      # map each sample request to a kai call, but do not actually create
  :dryrun,   # print out what we'd send to Kai API in an actual dispatch
  :dispatch, # use each sample to create an actual call
]

usage! if ARGV.empty?

mode = ARGV.first
host = ARGV.count >= 2 ? ARGV[1] : "localhost"
port = ARGV.count >= 3 ? ARGV[2].to_i : 4567
endpoint = endpoint_for_mode(mode) or usage!

puts "Testing #{mode} on #{host}:#{port}/#{endpoint}"
puts
samples.each do |sample|
  puts "Sample: #{sample.bold}"
  url = "http://#{host}:#{port}/#{endpoint}"
  data = IO.read(sample).strip
  puts data.light_black
  puts
  resp = RestClient.post(url, data, content_type: :json)

  puts "Response:"
  puts resp.body.to_s.green
  puts
  puts
end

