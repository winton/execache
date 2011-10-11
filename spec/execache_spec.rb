require 'spec_helper'

describe Execache do

  before(:all) do
    @thread = Thread.new do
      Execache.new("#{$root}/spec/fixtures/execache.yml")
    end
    @client = Execache::Client.new("localhost:6379/0")
  end

  after(:all) do
    @thread.kill
  end

  it "should" do
    puts @client.exec(
      :some_binary => {
        :args => 'preliminary_arg',
        :groups => [
          {
            :args => 'arg1a arg1b',
            :ttl => 60
          },
          {
            :args => 'arg2a arg2b',
            :ttl => 60
          }
        ]
      }
    ).inspect
  end
end