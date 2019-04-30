#!/usr/bin/ruby

require 'sinatra'
require 'json'
require 'colorize'

helpers do
  def print_value(value, indent=0)
    case value
    when Hash
      printf("\n")
      dump_hash(value, indent+1)
    when Array
      printf("\n")
      dump_array(value, indent+1)
    when Numeric
      printf("%s\n", value.to_s.yellow)
    else
      printf("%s\n", value)
    end
  end

  def dump_hash(hash, indent=0)
    max_key_len = hash.keys.map { |k| k.to_s.length }.max
    hash.each do |key, value|
      pad = "    " * indent
      printf("%s%#{max_key_len}s: ", pad, key.green)
      print_value(value)
    end
  end

  def dump_array(array, indent=0)
    array.each_with_index do |value, index|
      pad = "    " * indent
      printf("%s%s:  ", pad, sprintf("%3s", index.to_s).blue)
      print_value(value)
    end
  end

  def dump_req
    puts
    puts Time.now.to_s.red
    puts "#{request.request_method} #{request.url}".bold
    puts "User agent: #{request.user_agent}"
    puts "Referrer: #{request.referrer}"
    puts "IP: #{request.ip}"
    puts "Params: #{params.to_json}"
    puts "\nParams dump:".bold
    print_value(params)
    puts "\n\n"
    puts "Body: #{request.content_length} bytes, media type #{request.media_type}"
    puts request.body.read
    puts
    puts
  end
end

DEFAULT_PORT=4567
port = ARGV.first.to_i
port = DEFAULT_PORT if port.nil? || port <= 0
puts "Listening on: #{port.to_s.green.bold}"

set :port, port
set :bind, '0.0.0.0'

post '*' do
  dump_req
end

get '*' do
  dump_req
end

put '*' do
  dump_req
end

delete '*' do
  dump_req
end
