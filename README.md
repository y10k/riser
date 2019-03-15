Riser
=====

**RISER** is a library of **R**uby **I**nfrastructure for cooperative
multi-thread/multi-process **SER**ver.

This library is useful for the following.

* To make a server with tcp/ip or unix domain socket
* To select a method to execute server from:
    - Single process multi-thread
    - Preforked multi-process multi-thread
* To make a daemon that will be controlled by signal(2)s
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

Riser provids the function to daemonize server.  By daemonizing the
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

|callback                                         |description                                                                                            |
|-------------------------------------------------|-------------------------------------------------------------------------------------------------------|
|<code>before_start{&#124;server_socket&#124; ...}</code>|performed before starting the server. in a multi-process server, it is performed in the parent process.|
|`at_fork{ ... }`                                 |performed after fork(2)ing on the multi-process server. it is performed in the child process.          |
|<code>at_stop{&#124;stop_state&#124; ... }</code>|performed when a stop signal(2) is received. in a multi-process server, it is performed in the child process.|
|<code>at_stat{&#124;stat_info&#124; ... }</code> |performed when 'get stat' signal(2) is received.                                                       |
|`preprocess{ ... }`                              |performed before starting 'dispatch loop'. in a multi-process server, it is performed in the child process.|
|`postprocess{ ... }`                             |performed after 'dispatch loop' is finished. in a multi-process server, it is performed in the child process.|
|`after_stop{ ... }`                              |performed after the server stop. in a multi-process server, it is performed in the parent process.     |
|<code>dispatch{&#124;socket&#124; ... }</code>   |known dispatch callback. in a multi-process server, it is performed in the child process.              |

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

### TLS Server

With OpenSSL, the riser is able to provide a TLS server.  To provide a
TLS server you need a certificate and private key.  An example of a
simple TLS server is as follows.

```ruby
require 'openssl'
require 'riser'

cert_path = ARGV.shift or abort('need for server certificate file')
pkey_path = ARGV.shift or abort('need for server private key file')

Riser::Daemon.start_daemon(daemonize: false,
                           daemon_name: 'simple_tls',
                           listen_address: 'localhost:5000'
                          ) {|server|

  ssl_context = OpenSSL::SSL::SSLContext.new
  ssl_context.cert = OpenSSL::X509::Certificate.new(File.read(cert_path))
  ssl_context.key = OpenSSL::PKey.read(File.read(pkey_path))

  server.dispatch{|socket|
    ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, ssl_context)
    ssl_socket.accept
    while (line = ssl_socket.gets)
      ssl_socket.write(line)
    end
    ssl_socket.close
  }
}
```

An example of the result of connecting to the TLS server from OpenSSL
client is as follows.

```
$ openssl s_client -CAfile local_ca.cert -connect localhost:5000
CONNECTED(00000003)
depth=1 C = JP, ST = Tokyo, L = Tokyo, O = Private, OU = Home, CN = *
verify return:1
depth=0 C = JP, ST = Tokyo, L = Tokyo, O = Private, OU = Home, CN = localhost
verify return:1
---
Certificate chain
 0 s:/C=JP/ST=Tokyo/L=Tokyo/O=Private/OU=Home/CN=localhost
   i:/C=JP/ST=Tokyo/L=Tokyo/O=Private/OU=Home/CN=*
---
Server certificate
-----BEGIN CERTIFICATE-----
MIIDODCCAiACCQCks7GdVjzAmDANBgkqhkiG9w0BAQsFADBaMQswCQYDVQQGEwJK
UDEOMAwGA1UECAwFVG9reW8xDjAMBgNVBAcMBVRva3lvMRAwDgYDVQQKDAdQcml2
YXRlMQ0wCwYDVQQLDARIb21lMQowCAYDVQQDDAEqMB4XDTE5MDExNTA4MzYzMloX
DTI5MDExMjA4MzYzMlowYjELMAkGA1UEBhMCSlAxDjAMBgNVBAgMBVRva3lvMQ4w
DAYDVQQHDAVUb2t5bzEQMA4GA1UECgwHUHJpdmF0ZTENMAsGA1UECwwESG9tZTES
MBAGA1UEAwwJbG9jYWxob3N0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKC
AQEAvsrEIm1Unna7KM4U45ibGG/A4pnEScMymaLoitbVr5wAzvn/Oj2UkRO0gzQl
tLh28+jKh1eIlg60jyJ+QqpRCDWXXkEKXaAETbpYK1dlGE3ORI1VdTe/tYlpFxdd
Bzq//pQVNnYw6I+eu+VNIGroI7rWybsvpwPXgqaiyFlmrP9i8VdZKvKketc+NNwt
Chf81NJ9I1ue0cFZz+bMI84xhulVfxPi1avoXy0Ai+FM4Zqao5dkkKbmgia6R34e
J9P7FIGYHypj988fRVs2Pqprh60Zx32oJsLRZzgeiIUqkim3fWDs0TydxAuG6Owl
XgyCsdTGvwPM9ZQJQgczJsJCNwIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQCt0lUl
X1b+r7xAnnBdmxYfIkEoMeEhe5VUB+/Onixb8C3sIdzM8PdXo43OKe/lb9kKY7Gz
JQMFgrD4jc53mygU4K5gBXKZYOC3/NDNyqSr+22VHMqSD/pImjVFZ9E69gyqVXJ5
mQBUWgUU4QhpgMnOi0HsN1bpjTiHEaCo7ODlNtF3fhj0bC5CzofxnNMUjTJAn8Rh
A+fj/6dtDP+lMX//QkjtHOdVafKN8BJRrZg/DliGrqpUKW8h3NxCjGLeG5rFnVVj
qPFc7IbH25KMLMDCJ3xrqBVtOOEjdTFKbfqOo58HZD7f/PYdQ0XHpG+/f6s+TgTl
L+yNZF+/WlW7/020
-----END CERTIFICATE-----
subject=/C=JP/ST=Tokyo/L=Tokyo/O=Private/OU=Home/CN=localhost
issuer=/C=JP/ST=Tokyo/L=Tokyo/O=Private/OU=Home/CN=*
---
No client certificate CA names sent
Peer signing digest: SHA512
Server Temp Key: X25519, 253 bits
---
SSL handshake has read 1453 bytes and written 269 bytes
Verification: OK
---
New, TLSv1.2, Cipher is ECDHE-RSA-AES256-GCM-SHA384
Server public key is 2048 bit
Secure Renegotiation IS supported
Compression: NONE
Expansion: NONE
No ALPN negotiated
SSL-Session:
    Protocol  : TLSv1.2
    Cipher    : ECDHE-RSA-AES256-GCM-SHA384
    Session-ID: 43427207A2C36F807AF5BDCB69EF26F18758A5BAC5C4867C04B17E1C1F6CAE9D
    Session-ID-ctx:
    Master-Key: 7BE6C8E0108A6A2F9B2B6AC4DB8360EE375A950D2EB4CB2B259125FB17BE74F00120F7E7290B7137E16F665F44D8AD20
    PSK identity: None
    PSK identity hint: None
    SRP username: None
    TLS session ticket lifetime hint: 7200 (seconds)
    TLS session ticket:
    0000 - af bd 28 5e ca d4 ae 61-38 63 ff 68 84 2b 51 13   ..(^...a8c.h.+Q.
    0010 - d3 c5 7f c7 72 be f5 5c-bd 9e fb f3 88 61 83 01   ....r..\.....a..
    0020 - a5 11 fe 45 14 c1 9c 9b-79 7b 34 87 c1 66 e1 cd   ...E....y{4..f..
    0030 - 7d f4 ac 62 6e 25 53 c5-35 b2 b2 2c 3c b9 af 89   }..bn%S.5..,<...
    0040 - cf 11 1d 9c 42 5a 75 86-d1 6d 49 fc e9 6a 39 f0   ....BZu..mI..j9.
    0050 - fb cf 7d 9a 60 52 10 ad-a3 15 1b ba 00 32 67 e8   ..}.`R.......2g.
    0060 - 03 ea 74 49 17 46 d8 a2-41 45 17 9d 2c ec 7f 3f   ..tI.F..AE..,..?
    0070 - 89 eb 7e 4a 05 10 a3 81-d2 16 ce c7 da 7d c6 5a   ..~J.........}.Z
    0080 - 9c 50 de a5 ce 8e ca 58-af 0b 94 d2 2a c2 56 da   .P.....X....*.V.
    0090 - 00 05 b9 87 3c 9c 0e 53-70 c2 59 24 ef 0b 0a f3   ....<..Sp.Y$....

    Start Time: 1549358604
    Timeout   : 7200 (sec)
    Verify return code: 0 (ok)
    Extended master secret: yes
---
foo
foo
bar
bar
DONE
```

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
          socket << 'key: ' << key << "\n"
          socket << 'pid: ' << services.call_service(:pid_stickty, key) << "\n"
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
key: default
pid: 3181
$ curl http://localhost:8000/sticky
key: default
pid: 3181
$ curl http://localhost:8000/sticky?foo
key: foo
pid: 3179
$ curl http://localhost:8000/sticky?foo
key: foo
pid: 3179
$ curl http://localhost:8000/sticky?bar
key: bar
pid: 3185
$ curl http://localhost:8000/sticky?bar
key: bar
pid: 3185
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
          socket << 'key: ' << key << "\n"
          socket << 'pid: ' << services.call_service(:pid_stickty, key) << "\n"
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
key: default
pid: 3855
$ curl http://localhost:8000/sticky
key: default
pid: 3855
$ curl http://localhost:8000/sticky?foo
key: foo
pid: 3855
$ curl http://localhost:8000/sticky?foo
key: foo
pid: 3855
$ curl http://localhost:8000/sticky?bar
key: bar
pid: 3855
$ curl http://localhost:8000/sticky?bar
key: bar
pid: 3855
```

### dRuby Services Callbacks

The object of `Riser::DRbServices` is able to register callbacks.
The list of  callbacks is as follows.

|callback                                          |description                                               |
|--------------------------------------------------|----------------------------------------------------------|
|<code>at_fork(service_name) {&#124;service_front&#124; ... }</code>|performed when dRuby server process starts with remote process call. ignored by local process call.|
|<code>preprocess(service_name) {&#124;service_front&#124; ... }</code> |performed before starting the server.|
|<code>postprocess(service_name) {&#124;service_front&#124; ... }</code>|performed after the server stop.     |

### dRuby Services and Resource

An example of running a pstore database in a single process without
collision in a multi-process server is as follows.

```ruby
require 'pstore'
require 'riser'

Riser::Daemon.start_daemon(daemonize: false,
                           daemon_name: 'simple_count',
                           listen_address: 'localhost:8000'
                          ) {|server|

  services = Riser::DRbServices.new(1)
  services.add_single_process_service(:pstore, PStore.new('simple_count.pstore', true))

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
      method, _uri, _version = line.split
      while (line = socket.gets)
        line.strip.empty? and break
      end
      if (method == 'GET') then
        socket << "HTTP/1.0 200 OK\r\n"
        socket << "Content-Type: text/plain\r\n"
        socket << "\r\n"

        services.get_service(:pstore).transaction do |pstore|
          pstore[:count] ||= 0
          pstore[:count] += 1
          socket << 'count: ' << pstore[:count] << "\n"
        end
      end
    end
  }
  server.after_stop{
    services.stop_server
  }
}
```

The result of the web service in this example is as follows.

```
$ curl http://localhost:8000/
count: 1
$ curl http://localhost:8000/
count: 2
$ curl http://localhost:8000/
count: 3
$ ls -l *.pstore
-rw-r--r-- 1 toki toki 13 Feb  5 15:21 simple_count.pstore
```

An example of using an undefined number of pstore is as follows.  By
using `Riser::ResourceSet` and sticky process pattern, you can create
a pstore object on access by each key.

```ruby
require 'pstore'
require 'riser'

Riser::Daemon.start_daemon(daemonize: false,
                           daemon_name: 'simple_key_count',
                           listen_address: 'localhost:8000'
                          ) {|server|

  services = Riser::DRbServices.new(4)
  services.add_sticky_process_service(:pstore,
                                      Riser::ResourceSet.build{|builder|
                                        builder.at_create{|key|
                                          PStore.new("simple_key_count-#{key}.pstore", true)
                                        }
                                        builder.at_destroy{|pstore|
                                          # nothing to do about `pstore'.
                                        }
                                      })

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

        _path, query = uri.split('?', 2)
        key = query || 'default'
        services.call_service(:pstore, key) {|pstore|
          pstore.transaction do
            pstore[:count] ||= 0
            pstore[:count] += 1
            socket << 'key: ' << key << "\n"
            socket << 'count: ' << pstore[:count] << "\n"
          end
        }
      end
    end
  }
  server.after_stop{
    services.stop_server
  }
}
```

The result of the web service in this example is as follows.

```
$ curl http://localhost:8000/
key: default
count: 1
$ curl http://localhost:8000/
key: default
count: 2
$ curl http://localhost:8000/
key: default
count: 3
$ curl http://localhost:8000/?foo
key: foo
count: 1
$ curl http://localhost:8000/?foo
key: foo
count: 2
$ curl http://localhost:8000/?foo
key: foo
count: 3
$ curl http://localhost:8000/?bar
key: bar
count: 1
$ curl http://localhost:8000/?bar
key: bar
count: 2
$ curl http://localhost:8000/?bar
key: bar
count: 3
$ ls -l *.pstore
-rw-r--r-- 1 toki toki 13 Feb  5 16:16 simple_key_count-bar.pstore
-rw-r--r-- 1 toki toki 13 Feb  5 16:15 simple_key_count-default.pstore
-rw-r--r-- 1 toki toki 13 Feb  5 16:15 simple_key_count-foo.pstore
```

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
