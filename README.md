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

### Server Attributes

The server has attributes, and setting attributes changes the behavior
of the server.  Let's take an example `process_num` attribute.  The
`process_num` attribute is `0` by default, but by setting it will run
the server with multi-process.

In the following example, `process_num` is set to `2`.
Others are the same as simple server example.

```ruby
require 'riser'
require 'socket'

server = Riser::SocketServer.new
server.process_num = 2
server.dispatch{|socket|
  while (line = socket.gets)
    socket.write(line)
  end
}

server_socket = TCPServer.new('localhost', 5000)
server.start(server_socket)
```

Running the example will hardly change the appearance, but the server
is running with multi-process.  You can see that the server is running
in multiple processes with `pstree` command.

```
$ pstree -ap
...
  |   `-bash,23355
  |       `-ruby,31283 multiproc_server.rb
  |           |-ruby,31284 multiproc_server.rb
  |           |   |-{ruby},31285
  |           |   |-{ruby},31286
  |           |   |-{ruby},31287
  |           |   `-{ruby},31288
  |           |-ruby,31289 multiproc_server.rb
  |           |   |-{ruby},31292
  |           |   |-{ruby},31293
  |           |   |-{ruby},31294
  |           |   `-{ruby},31295
  |           |-{ruby},31290
  |           `-{ruby},31291
...
```

There are 2 child processes (`|-ruby`) under the parent process
(`` `-ruby``) having 2 threads , and 4 threads are running for each
child process.  The architecture of riser's multi-process server is
the passing file descriptors between parent-child processes.  The
parent process accepts the connection and passes it to threads, each
thread passes the connection to the child process, and `dispatch`
callback is performed in the thread of each child process.

In addition to `process_num`, the server object has various attributes
such as `thread_num`.  See the source code
([server.rb/Riser::SocketServer](https://github.com/y10k/riser/blob/master/lib/riser/server.rb))
for details of other attributes.

### Daemon

Riser provids the function to daemonize servers.  By daemonizing the
server, the server will be able to receive signal(2)s and restart.  An
example of a simple daemon is as follows.

```ruby
require 'riser'

Riser::Daemon.start_daemon(daemonize: true,
                           daemon_name: 'simple_daemon',
                           status_file: 'simple_daemon.pid',
                           listen_address: 'localhost:5000'
                          ) {|server|

  server.dispatch{|socket|
    while (line = socket.gets)
      socket.write(line)
    end
  }
}
```

To daemonize the server, use the module function of
`Riser::Daemon.start_daemon`.  The `start_daemon` function takes
parameters in a hash table and works.  The works of `start_daemon` are
as follows.

1. Daemonize the server process (`daemonize: true`).
2. Output syslog(2) identified with `simple_daemon`
   (`daemon_name: 'simple_daemon'`).
3. Output process id to the file of `simple_daemon.pid` and lock it
   exclusively (`status_file: 'simple_daemon.pid'`).
4. Open the tcp/ip server socket of `localhost:5000`
   (`listen_address: 'localhost:5000'`).
5. Create a server object and pass it to the block, and you set up the
   server object in the block, then `start` the server object.

A command prompt is displayed as soon as you start the daemon, but the
daemon runs in the background and logs to syslog(2).  Daemonization is
the result of `daemonaize: true`.  If `daemonaize: false` is set, the
process is not daemonized, starts in foreground and logs to standard
output.  This is useful for debugging daemon.

Looking at the process of the daemon with `pstree` command is as
follows.

```
$ pstree -ap
init,1 ro
  |-ruby,32187 simple_daemon.rb
  |   `-ruby,32188 simple_daemon.rb
  |       |-{ruby},32189
  |       |-{ruby},32190
  |       |-{ruby},32191
  |       `-{ruby},32192
...
```

The daemon process is running as the parent of the server process.
And the daemon process is running independently under the init(8)
process.  The daemon process monitors the server process and restarts
when the server process dies.  Also, the daemon process receives some
signal(2)s and stops or restarts the server process, and does other
things.

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
