class Execache
  class Client

    attr_reader :redis_1, :redis_2

    def initialize(redis_url)
      @redis_1 = Redis.connect(:url => "redis://#{redis_url}")
      @redis_2 = Redis.connect(:url => "redis://#{redis_url}")
    end

    def exec(options)
      wait = options.delete(:wait)
      subscribe_to = options[:channel] = Digest::SHA1.hexdigest("#{rand}")
      options = Yajl::Encoder.encode(options)
      response = nil

      Timeout.timeout(60) do
        @redis_1.subscribe("execache:response:#{subscribe_to}") do |on|
          on.subscribe do |channel, subscriptions|
            @redis_2.rpush "execache:request", options
          end

          on.message do |channel, message|
            if message.include?('[PENDING]')
              if wait == false
                response = false
                @redis_1.unsubscribe
              else  
                @redis_2.rpush "execache:request", options
              end
            else
              response = Yajl::Parser.parse(message)
              @redis_1.unsubscribe
            end
          end
        end
      end

      response
    end
  end
end