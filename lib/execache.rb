require "digest/sha1"
require "timeout"
require "yaml"

gem "yajl-ruby", "~> 1.0.0"
require "yajl"

gem "redis", "~> 2.2.2"
require "redis"

$:.unshift File.dirname(__FILE__)

require 'execache/client'

class Execache

  def initialize(yaml)
    options = YAML.load(File.read(yaml))

    puts "\nStarting execache server (redis @ #{options['redis']})..."

    redis = Redis.connect(:url => "redis://#{options['redis']}")
    retries = 0
    
    begin
      while true
        request = redis.lpop('execache:request')
        if request
          Thread.new do
            request = Yajl::Parser.parse(request)
            channel = request.delete('channel')
            commands = []

            request.each do |cmd_type, cmd_options|
              # Command with preliminary args
              command = [
                options[cmd_type]['command'],
                cmd_options['args']
              ]
              
              # Fill results with caches if present
              cmd_options['groups'].each do |group|
                cache_key = Digest::SHA1.hexdigest(
                  "#{cmd_options['args']} #{group['args']}"
                )
                group['cache_key'] = cache_key = "execache:cache:#{cache_key}"
                cache = redis.get(cache_key)
                
                if cache
                  group['result'] = Yajl::Parser.parse(cache)
                else
                  command << group['args']
                  nil
                end
              end
              
              # Add command to be executed if not all args are cached
              if command.length > 2
                cmd_options['cmd'] = command.join(' ')
              end
            end

            # Build response
            response = request.inject({}) do |hash, (cmd_type, cmd_options)|
              hash[cmd_type] = []

              if cmd_options['cmd']
                separators = options[cmd_type]['separators']
                output = `#{cmd_options['cmd']}`
                output = output.split(separators['group'] + separators['result'])
                output = output.collect { |r| r.split(separators['result']) }
              end

              cmd_options['groups'].each do |group|
                if group['result']
                  hash[cmd_type] << group['result']
                else
                  hash[cmd_type] << output.shift
                  redis.set(
                    group['cache_key'],
                    Yajl::Encoder.encode(hash[cmd_type].last)
                  )
                  if group['ttl']
                    redis.expire(group['cache_key'], group['ttl'])
                  end
                end
              end

              hash
            end
            
            redis.publish(
              "execache:response:#{channel}",
              Yajl::Encoder.encode(response)
            )
          end
        end
        sleep(1.0 / 1000.0)
      end
    rescue Interrupt
      shut_down
    rescue Exception => e
      puts "\nError: #{e.message}"
      puts "\t#{e.backtrace.join("\n\t")}"
      retries += 1
      shut_down if retries >= 10
      retry
    end
  end

  def shut_down
    puts "\nShutting down execache server..."
    exit
  end
end