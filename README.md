Execache
========

Run commands in parallel and cache the output. Redis queues jobs and stores the result.

Requirements
------------

<pre>
gem install execache
</pre>

How Your Binaries Should Behave
-------------------------------

Execache assumes that the script or binary you are executing has multiple results and sometimes multiple groups of results.

Example output:

    $ bin/some/binary preliminary_arg arg1a arg1b arg2a arg2b
    $ arg1_result_1
    $ arg1_result_2
    $ [END]
    $ arg2_result_1
    $ arg2_result_2

Your binary may take zero or more preliminary arguments (e.g. `preliminary_arg`), followed by argument "groups" that dictate output (e.g. `arg1a arg1b`).

Configure
---------

Given the above example, our `execache.yml` looks like this:

    redis: localhost:6379/0
    some_binary:
      command: '/bin/some/binary'
      separators:
        result: "\n"
        group: "[END]"

Start the Server
----------------

    $ execache /path/to/execache.yml

Execute Commands
----------------

    require 'rubygems'
    require 'execache'

    client = Execache::Client.new("localhost:6379/0")
    
    results = client.exec(
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

    results == {
      :some_binary => [
        [ 'arg1_result_1', 'arg1_result_2' ],
        [ 'arg2_result_1', 'arg2_result_2' ]
      ]
    }