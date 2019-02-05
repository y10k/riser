Riser
=====

RISER is a library of **R**uby **I**nfrastructure for cooperative
multi-thread/multi-process **SER**ver.

This library is useful for the following.

* To make a server with tcp/ip or unix domain socket
* To choose a method to execute server from:
    - Single process multi-thread
	- Preforked multi-process multi-thread
* To make a daemon that wil be controlled by signal(2)s
* To separate the object not divided into multiple processes from
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
([server.rb: Riser::SocketServer](https://github.com/y10k/riser/blob/master/lib/riser/server.rb))
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

### Signal(2)s and Other Daemon Parameters

By default, the daemon is able to receive the following signal(2)s.

|signal(2)|daemon's action                       |`start_daemon` parameter   |
|---------|--------------------------------------|---------------------------|
|`TERM`   |stop server gracefully                |`signal_stop_graceful`     |
|`INT`    |stop server forcedly                  |`signal_stop_forced`       |
|`HUP`    |restart server gracefully             |`signal_restart_graceful`  |
|`QUIT`   |restart server forcedly               |`signal_restart_forced`    |
|`USR1`   |get queue stat and reset queue stat   |`signal_stat_get_and_reset`|
|`USR2`   |get queue stat and no reset queue stat|`signal_stat_get_no_reset` |
|`WINCH`  |stop queue stat                       |`signal_stat_stop`         |

By setting the parameters of the `start_daemon`, you can change the
signal(2) which triggers the action.  Setting the parameter to `nil`
will disable the action.  'Queue stat' is explained later.

The `start_daemon` has other parameters.  See the source code
([daemon.rb: Riser::Daemon::DEFAULT](https://github.com/y10k/riser/blob/master/lib/riser/daemon.rb))
for details of other parameters.

### Server Callbacks

The server object is able to register callbacks other than `dispatch`.
The list of server objects' callbacks is as follows.

|callback                           |description                                                                                                  |
|-----------------------------------|-------------------------------------------------------------------------------------------------------------|
|`before_start{|server_socket| ...}`|performed before starting the server. in a multi-process server, it is performed in the parent process.      |
|`at_fork{ ... }`                   |performed after fork(2)ing on the multi-process server. it is performed in the child process.                |
|`at_stop{|stop_state| ... }`       |performed when a stop signal(2) is received. in a multi-process server, it is performed in the child process.|
|`at_stat{|stat_info| ... }`        |performed when 'get stat' signal(2) is received.                                                             |
|`preprocess{ ... }`                |performed before starting 'dispatch loop'. in a multi-process server, it is performed in the child process.  |
|`postprocess{ ... }`               |performed after 'dispatch loop' is finished. in a multi-process server, it is performed in the child process.|
|`after_stop{ ... }`                |performed after the server stop. in a multi-process server, it is performed in the parent process.           |
|`dispatch{|socket| ... }`          |known dispatch callback. in a multi-process server, it is performed in the child process.                    |

It seems necessary to explain the `at_stat` callback.  Riser uses
queues to distribute connections to threads and processes, and it is
possible to get statistics information on queues.  With `USR1` and
`USR2` signal(2)s, you can start collecting queue statistics
information and get it.  At that time the `at_stat` callback is called
and used to write queue statistics informations to log etc.  With the
`WINCH` signal(2), you can stop collecting queue statistics
information.

For a example of how to use callbacks, see the source code of the
'[halo.rb](https://github.com/y10k/riser/blob/master/example/halo.rb)'
example.

### Server Utilities

Riser provides some useful utilities to  write a server.

|utility                   |description              |
|--------------------------|-------------------------|
|`Riser::ReadPoll`         |monitor I/O timeout.     |
|`Riser::WriteBufferStream`|buffer I/O writes.       |
|`Riser::LoggingStream`    |log I/O read / write.    |

For a example of how to use utilities, see the source code of the
'[halo.rb](https://github.com/y10k/riser/blob/master/example/halo.rb)'
example.  Also utilities are simple, so check the source codes of
'[poll.rb](https://github.com/y10k/riser/blob/master/lib/riser/poll.rb)'
and
'[stream.rb](https://github.com/y10k/riser/blob/master/lib/riser/stream.rb)'.

### dRuby Services

Riser has a mechanism that runs the object in a separate process from
the server process.  This mechanism pools the dRuby server processes
and distributes the object to them in the following 3 patterns.

|pattern       |description                                              |
|--------------|---------------------------------------------------------|
|any process   |run the object with a randomly picked process.           |
|single process|always run the object in the same process.               |
|sticky process|run the object in the same process for each specific key.|

A simple example of how this mechanism works is as follows.

```ruby
require 'riser'

Riser::Daemon.start_daemon(daemonize: false,
                           daemon_name: 'simple_services',
                           listen_address: 'localhost:8000'
                          ) {|server|

  services = Riser::DRbServices.new(4)
  services.add_any_process_service(:pid_any, proc{ $$ })
  services.add_single_process_service(:pid_single, proc{ $$ })
  services.add_sticky_process_service(:pid_stickty, proc{|key| $$ })

  server.process_num = 2
  server.before_start{|server_socket|
    services.start_server
  }
  server.at_fork{
    services.detach_server
  }
  server.preprocess{
    services.start_client
  }
  server.dispatch{|socket|
    if (line = socket.gets) then
      method, uri, _version = line.split
      while (line = socket.gets)
        line.strip.empty? and break
      end
      if (method == 'GET') then
        socket << "HTTP/1.0 200 OK\r\n"
        socket << "Content-Type: text/plain\r\n"
        socket << "\r\n"

        path, query = uri.split('?', 2)
        case (path)
        when '/any'
          socket << 'pid: ' << services.call_service(:pid_any) << "\n"
        when '/single'
          socket << 'pid: ' << services.call_service(:pid_single) << "\n"
        when '/sticky'
          key = query || 'default'
          socket << 'key: ' << key << ', pid: ' << services.call_service(:pid_stickty, key) << "\n"
        else
          socket << "unknown path: #{path}\n"
        end
      end
    end
  }
  server.after_stop{
    services.stop_server
  }
}
```

`Riser::DRbServices` is the mechanism for distributing objects.  What
this example does is as follows.

1. Create a object of `Riser::DRbServices` to pool 4 dRuby server
   processes (`Riser::DRbServices.new(4)`).
2. Add objects to run in dRuby server process
   (`add_..._process_service`).  In this example it is added that the
   procedures that returns the process id to see the process to be
   distributed the object.
3. Start dRuby server process with `start_server`.  In the case of a
   multi-process server, it is necessary to execute `start_server` in
   the parent process, so it is executed at `before_start` callback.
4. In the case of a multi-process server, execute `detach_server` at
   `at_fork` callback to release unnecessary resources in the child
   process.
5. Start dRuby client with `start_client`.  In the case of a
   multi-process server, it is necessary to execute `start_client` in
   the child process, so it is executed at `preprocess` callback.
6. Add the processing of the web service at `dispatch` callback.  The
   procedures added to `Riser::DRbServices` are able to be called by
   `call_service`.  For object other than procedure, use
   `get_service`.
7. Stop dRuby server process with `stop_server`.  In the case of a
   multi-process server, it is necessary to execute `stop_server` in
   the parent process, so it is executed at `after_stop` callback.

In this example, you can see the dRuby process distribution with a
simple web service.  Looking at the process of this example with
`pstree` command is as follows.

```
$ pstree -ap
...
  |   `-bash,23355
  |       `-ruby,3177 simple_services.rb
  |           `-ruby,3178 simple_services.rb
  |               |-ruby,3179 simple_services.rb
  |               |   |-{ruby},3180
  |               |   |-{ruby},3189
  |               |   `-{ruby},3198
  |               |-ruby,3181 simple_services.rb
  |               |   |-{ruby},3182
  |               |   |-{ruby},3194
  |               |   `-{ruby},3202
  |               |-ruby,3183 simple_services.rb
  |               |   |-{ruby},3184
  |               |   |-{ruby},3197
  |               |   `-{ruby},3207
  |               |-ruby,3185 simple_services.rb
  |               |   |-{ruby},3186
  |               |   |-{ruby},3201
  |               |   `-{ruby},3211
  |               |-ruby,3187 simple_services.rb
  |               |   |-{ruby},3188
  |               |   |-{ruby},3191
  |               |   |-{ruby},3195
  |               |   |-{ruby},3199
  |               |   |-{ruby},3203
  |               |   |-{ruby},3205
  |               |   |-{ruby},3206
  |               |   |-{ruby},3208
  |               |   `-{ruby},3209
  |               |-ruby,3190 simple_services.rb
  |               |   |-{ruby},3196
  |               |   |-{ruby},3200
  |               |   |-{ruby},3204
  |               |   |-{ruby},3210
  |               |   |-{ruby},3212
  |               |   |-{ruby},3213
  |               |   |-{ruby},3214
  |               |   |-{ruby},3215
  |               |   `-{ruby},3216
  |               |-{ruby},3192
  |               `-{ruby},3193
...
```

In addition to the 2 server child processes with many threads, there
are 4 child processes.  These 4 child processes are dRuby server
processes.  See the web service's result of 'any process' pattern.

```
$ curl http://localhost:8000/any
pid: 3181
$ curl http://localhost:8000/any
pid: 3179
$ curl http://localhost:8000/any
pid: 3183
$ curl http://localhost:8000/any
pid: 3181
```

In the 'any process' pattern, process ids are dispersed.  Next, see
the web service's result of 'single process' pattern.

```
$ curl http://localhost:8000/single
pid: 3179
$ curl http://localhost:8000/single
pid: 3179
$ curl http://localhost:8000/single
pid: 3179
$ curl http://localhost:8000/single
pid: 3179
```

In the 'single process' pattern, process id is always same.  Last, see
the web service's result of 'sticky process' pattern.

```
$ curl http://localhost:8000/sticky
key: default, pid: 3181
$ curl http://localhost:8000/sticky
key: default, pid: 3181
$ curl http://localhost:8000/sticky?foo
key: foo, pid: 3179
$ curl http://localhost:8000/sticky?foo
key: foo, pid: 3179
$ curl http://localhost:8000/sticky?bar
key: bar, pid: 3185
$ curl http://localhost:8000/sticky?bar
key: bar, pid: 3185
```

In the 'sticky process' pattern, the same process id will be given for
each key.

### Local Services

Since dRuby's remote process call has overhead, riser is able to
transparently switch `Riser::DRbServices` to local process call.  An
example of a local process call is as follows.

```ruby
require 'riser'

Riser::Daemon.start_daemon(daemonize: false,
                           daemon_name: 'local_services',
                           listen_address: 'localhost:8000'
                          ) {|server|

  services = Riser::DRbServices.new(0)
  services.add_any_process_service(:pid_any, proc{ $$ })
  services.add_single_process_service(:pid_single, proc{ $$ })
  services.add_sticky_process_service(:pid_stickty, proc{|key| $$ })

  server.process_num = 0
  server.before_start{|server_socket|
    services.start_server
  }
  server.at_fork{
    services.detach_server
  }
  server.preprocess{
    services.start_client
  }
  server.dispatch{|socket|
    if (line = socket.gets) then
      method, uri, _version = line.split
      while (line = socket.gets)
        line.strip.empty? and break
      end
      if (method == 'GET') then
        socket << "HTTP/1.0 200 OK\r\n"
        socket << "Content-Type: text/plain\r\n"
        socket << "\r\n"

        path, query = uri.split('?', 2)
        case (path)
        when '/any'
          socket << 'pid: ' << services.call_service(:pid_any) << "\n"
        when '/single'
          socket << 'pid: ' << services.call_service(:pid_single) << "\n"
        when '/sticky'
          key = query || 'default'
          socket << 'key: ' << key << ', pid: ' << services.call_service(:pid_stickty, key) << "\n"
        else
          socket << "unknown path: #{path}\n"
        end
      end
    end
  }
  server.after_stop{
    services.stop_server
  }
}
```

The differences from the previous example is as follows.

|code                       |description                                                                                                  |
|---------------------------|-------------------------------------------------------------------------------------------------------------|
|`Riser::DRbServices.new(0)`|setting the number of processes to `0` makes local process call without starting the dRuby server processes. |
|`server.process_num = 0`   |since local process call fails if it is a multi-process server, set it to single process multi-thread server.|

In this example, there are no dRuby server processes and there is only
1 server process.  Looking at the process of this example with
`pstree` command is as follows.

```
$ pstree -ap
...
  |   `-bash,23355
  |       `-ruby,3854 local_services.rb
  |           `-ruby,3855 local_services.rb
  |               |-{ruby},3856
  |               |-{ruby},3857
  |               |-{ruby},3858
  |               |-{ruby},3859
  |               `-{ruby},3860
...
```

The result of the web service always returns the same process id.

```
$ curl http://localhost:8000/any
pid: 3855
$ curl http://localhost:8000/any
pid: 3855
$ curl http://localhost:8000/any
pid: 3855
```

```
$ curl http://localhost:8000/single
pid: 3855
$ curl http://localhost:8000/single
pid: 3855
$ curl http://localhost:8000/single
pid: 3855
```

```
$ curl http://localhost:8000/sticky
key: default, pid: 3855
$ curl http://localhost:8000/sticky
key: default, pid: 3855
$ curl http://localhost:8000/sticky?foo
key: foo, pid: 3855
$ curl http://localhost:8000/sticky?foo
key: foo, pid: 3855
$ curl http://localhost:8000/sticky?bar
key: bar, pid: 3855
$ curl http://localhost:8000/sticky?bar
key: bar, pid: 3855
```

### dRuby Services Callbacks

The object of `Riser::DRbServices` is able to register callbacks.
The list of  callbacks is as follows.

|callback                                          |description                                                                                        |
|--------------------------------------------------|---------------------------------------------------------------------------------------------------|
|`at_fork(service_name) {|service_front| ... }`    |performed when dRuby server process starts with remote process call. ignored by local process call.|
|`preprocess(service_name) {|service_front| ... }` |performed before starting the server.                                                              |
|`postprocess(service_name) {|service_front| ... }`|performed after the server stop.                                                                   |

### Resource and ResouceSet

Development
-----------

After checking out the repo, run `bin/setup` to install
dependencies. You can also run `bin/console` for an interactive prompt
that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake
install`. To release a new version, update the version number in
`version.rb`, and then run `bundle exec rake release`, which will
create a git tag for the version, push git commits and tags, and push
the `.gem` file to [rubygems.org](https://rubygems.org).

Contributing
------------

Bug reports and pull requests are welcome on GitHub at
<https://github.com/y10k/riser>.

License
-------

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
