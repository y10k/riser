Riser
=====

RISER is a library of **R**uby **I**nfrastructure for cooperative
multi-thread/multi-process **SER**ver.

This library is useful for the following.

* to make a server with tcp/ip or unix domain socket
* to choose a method to execute server from:
    - single process multi-thread
	- preforked multi-process multi-thread
* to make a daemon that wil be controlled by signal(2)s
* to separate singleton task not divided into multiple processes from
  server process(es) into backend service process

This library supposes that the user is familiar with the unix process
model and socket programming.

Installation
------------

Add this line to your application's Gemfile:

```ruby
gem 'riser'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install riser

Usage
-----

### Simple Server Example

An example of a simple server is as follows.

```ruby
require 'riser'
require 'socket'

server = Riser::SocketServer.new
server.dispatch{|socket|
  while (line = socket.gets)
    socket.write(line)
  end
}

server_socket = TCPServer.new('localhost', 5000)
server.start(server_socket)
```

This simple server is an echo server that accepts connections at port
number 5000 on localhost and returns the input line as is.  The object
of `Riser::SocketServer` is the core of riser.  What this example does
is as follows.

1. Create a new server object of `Riser::SocketServer`.
2. Register `dispatch` callback to the server object.
3. Open a tcp/ip server socket.
4. Pass the server socket to the server object and `start` the server.

In this example tcp/ip socket is used, but the server will also work
with unix domain socket.  By rewriting the `dispatch` callback you can
make the server do what you want.  Although this example is
simplified, error handling is actually required.  If an exception is
thrown to outside of the `dispatch` callback, the server stops, so it
should be avoided.  See the
'[halo.rb](https://github.com/y10k/riser/blob/master/example/halo.rb)'
example for practical code.

By default, the server performs `dispatch` callback on multi-thread.
On Linux, you can see that running the server with 4 threads
(`{ruby}`) by executing `pstree` command.

```
$ pstree -ap
...
  |   `-bash,23355
  |       `-ruby,30674 simple_server.rb
  |           |-{ruby},30675
  |           |-{ruby},30676
  |           |-{ruby},30677
  |           `-{ruby},30678
...
```

Development
-----------

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

Contributing
------------

Bug reports and pull requests are welcome on GitHub at <https://github.com/y10k/riser>.

License
-------

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
