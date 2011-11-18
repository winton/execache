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
    parallel = options['parallel'] || 3

    puts "\nStarting execache server (redis @ #{options['redis']})..."

    redis = Redis.connect(:url => "redis://#{options['redis']}")
    retries = 0
    
    begin
      while true
        if request = redis.lpop('execache:request')
          Timeout.timeout(60) do
            request = Yajl::Parser.parse(request)

            # Options
            global_cache_key = request.delete('cache_key')
            channel = request.delete('channel')
            force = request.delete('force')
            ttl = request.delete('ttl')

            pending = false
            results = {}

            request.each do |cmd_type, cmd_options|
              cache_keys = []
              groups = []

              # Binary + preliminary arguments
              command = [
                options[cmd_type]['command'],
                cmd_options['args']
              ].join(' ')
              
              # For each argument group...
              cmd_options['groups'].each do |args|
                cache_key = Digest::SHA1.hexdigest(
                  "#{global_cache_key || command} #{args}"
                )
                cache_key = "execache:cache:#{cache_key}"
                cache = redis.get(cache_key)

                # If force cache overwrite || no cache || pending cache
                if force || !cache || cache == '[PENDING]'
                  pending = true
                
                # Else, store cache result
                else
                  results[cmd_type] ||= []
                  results[cmd_type] << Yajl::Parser.parse(cache)
                end

                # If force cache overwrite || no cache
                if force || !cache
                  redis.set(cache_key, '[PENDING]')
                  redis.expire(cache_key, 60) # Timeout incase execution fails

                  cache_keys << cache_key
                  groups << args
                end
              end
              
              # Add to command queue if commands present
              unless groups.empty?
                command = {
                  :cache_keys => cache_keys,
                  :cmd_type => cmd_type,
                  :command => command,
                  :groups => groups,
                  :ttl => ttl
                }
                redis.rpush("execache:commands", Yajl::Encoder.encode(command))
              end
            end
            
            redis.publish(
              "execache:response:#{channel}",
              pending ? '[PENDING]' : Yajl::Encoder.encode(results)
            )
          end
        end

        # Execute queued commands
        if redis.get("execache:parallel").to_i <= parallel && cmd = redis.lpop("execache:commands")
          redis.incr("execache:parallel")
          Thread.new do
            Timeout.timeout(60) do
              cmd = Yajl::Parser.parse(cmd)

              cache_keys = cmd['cache_keys']
              cmd_type = cmd['cmd_type']
              command = cmd['command']
              groups = cmd['groups']
              ttl = cmd['ttl']

              separators = options[cmd_type]['separators'] || {}
              separators['group'] ||= "[END]"
              separators['result'] ||= "\n"

              results = `#{command} #{groups.join(' ')}`
              results = results.split(separators['group'] + separators['result'])
              results = results.collect { |r| r.split(separators['result']) }

              redis.decr("execache:parallel")

              results.each_with_index do |result, i|
                redis.set(
                  cache_keys[i],
                  Yajl::Encoder.encode(result)
                )
                redis.expire(cache_keys[i], ttl) if ttl
              end
            end
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