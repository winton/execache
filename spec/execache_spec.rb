require 'spec_helper'

describe Execache do

  def client_exec
    @client.exec(
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
    )
  end

  before(:all) do
    @thread = Thread.new do
      Execache.new("#{$root}/spec/fixtures/execache.yml")
    end
    @client = Execache::Client.new("localhost:6379/0")
    @client.redis_1.keys("execache:cache:*").each do |key|
      @client.redis_1.del(key)
    end
  end

  after(:all) do
    @thread.kill
  end

  it "should return proper results" do
    client_exec.should == {
      "some_binary" => [
        ["arg1_result_1", "arg1_result_2"],
        ["arg2_result_1", "arg2_result_2"]
      ]
    }
  end

  it "should write to cache" do
    keys = @client.redis_1.keys("execache:cache:*")
    keys.length.should == 2
  end

  it "should read from cache" do
    keys = @client.redis_1.keys("execache:cache:*")
    @client.redis_1.set(keys[0], "[\"cached!\"]")
    @client.redis_1.set(keys[1], "[\"cached!\"]")
    client_exec.should == {
      "some_binary" => [
        ["cached!"],
        ["cached!"]
      ]
    }
  end

  it "should read from cache for individual groups" do
    @client.exec(
      :some_binary => {
        :args => 'preliminary_arg',
        :groups => [
          {
            :args => 'arg2a arg2b',
            :ttl => 60
          }
        ]
      }
    ).should == {
      "some_binary" => [
        ["cached!"]
      ]
    }

    @client.exec(
      :some_binary => {
        :args => 'preliminary_arg',
        :groups => [
          {
            :args => 'arg1a arg1b',
            :ttl => 60
          }
        ]
      }
    ).should == {
      "some_binary" => [
        ["cached!"]
      ]
    }
  end

  it "should not read cache if preliminary arg changes" do
    @client.exec(
      :some_binary => {
        :args => 'preliminary_arg2',
        :groups => [
          {
            :args => 'arg2a arg2b',
            :ttl => 60
          }
        ]
      }
    ).should == {
      "some_binary" => [
        ["arg1_result_1", "arg1_result_2"]
      ]
    }
  end

  it "should still read from original cache" do
    client_exec.should == {
      "some_binary" => [
        ["cached!"],
        ["cached!"]
      ]
    }
  end
end