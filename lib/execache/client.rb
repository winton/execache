class Execache
  class Client

    attr_reader :redis_1, :redis_2

    def initialize(redis_url)
      @redis_1 = Redis.connect(:url => "redis://#{redis_url}")
      @redis_2 = Redis.connect(:url => "redis://#{redis_url}")
    end

    def exec(options)
      options[:channel] = Digest::SHA1.hexdigest("#{rand}")
      response = nil

      Timeout.timeout(60) do
        @redis_1.subscribe("execache:response:#{options[:channel]}") do |on|
          on.subscribe do |channel, subscriptions|
            @redis_2.rpush "execache:request", Yajl::Encoder.encode(options)
          end

          on.message do |channel, message|
            response = Yajl::Parser.parse(message)
            @redis_1.unsubscribe
          end
        end
      end

      response
    end
  end
end