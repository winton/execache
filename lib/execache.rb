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
          Timeout.timeout(60) do
            request = Yajl::Parser.parse(request)
            channel = request.delete('channel')
            force = request.delete('channel')
            commands = []
            pending = false

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
                
                if cache && cache == '[PENDING]'
                  pending = true
                  group['result'] = true
                elsif !force && !group['force'] && cache
                  group['result'] = Yajl::Parser.parse(cache)
                else
                  pending = true
                  redis.set(cache_key, '[PENDING]')
                  redis.expire(cache_key, 60) # Timeout incase execution fails
                  command << group['args']
                end
              end
              
              # Add command to be executed if not all args are cached
              if command.length > 2
                cmd_options['cmd'] = command.join(' ')
              end
            end

            if pending
              # Execute command in thread, cache results
              Thread.new do
                Timeout.timeout(60) do
                  request.each do |cmd_type, cmd_options|
                    if cmd_options['cmd']
                      separators = options[cmd_type]['separators'] || {}
                      separators['group'] ||= "[END]"
                      separators['result'] ||= "\n"
                      output = `#{cmd_options['cmd']}`
                      output = output.split(separators['group'] + separators['result'])
                      output = output.collect { |r| r.split(separators['result']) }
                    end

                    cmd_options['groups'].each do |group|
                      unless group['result']
                        redis.set(
                          group['cache_key'],
                          Yajl::Encoder.encode(output.shift)
                        )
                        if group['ttl']
                          redis.expire(group['cache_key'], group['ttl'])
                        end
                      end
                    end
                  end
                end
              end
            else
              response = request.inject({}) do |hash, (cmd_type, cmd_options)|
                hash[cmd_type] = []

                cmd_options['groups'].each do |group|
                  hash[cmd_type] << group['result']
                end

                hash
              end
            end
            
            redis.publish(
              "execache:response:#{channel}",
              pending ? '[PENDING]' : Yajl::Encoder.encode(response)
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