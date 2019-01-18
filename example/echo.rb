#!/usr/local/bin/ruby
# -*- coding: utf-8 -*-

require 'logger'
require 'riser'
require 'socket'

socket_config = ARGV.shift || 'localhost:50000'
socket_address = Riser::SocketAddress.parse(socket_config)

server = Riser::SocketServer.new
server.process_num = 4

Signal.trap('TERM') { server.signal_stop_graceful }
Signal.trap('INT') { server.signal_stop_forced }
Signal.trap('QUIT') { server.signal_stop_forced }
Signal.trap('USR1') { server.signal_stat_get(reset: true) }
Signal.trap('USR2') { server.signal_stat_get(reset: false) }
Signal.trap('WINCH') { server.signal_stat_stop }

server.before_start{|server_socket|
  puts "before start (pid: #{Process.pid})"
  puts "listen #{server_socket.local_address.inspect_sockaddr}"
}
server.at_fork{ puts "fork: #{Process.ppid} -> #{Process.pid}" }
server.at_stop{|state| puts "stop: #{state} (pid: #{Process.pid})" }
server.at_stat{|info| puts info.pretty_inspect }
server.preprocess{ puts "preprocess (pid: #{Process.pid})" }
server.postprocess{ puts "postprocess (pid: #{Process.pid})" }
server.after_stop{ puts "after stop (pid: #{Process.pid})" }

stdout_log = Logger.new(STDOUT)

server.dispatch{|socket|
  begin
    read_poll = Riser::ReadPoll.new(socket)
    stream = Riser::WriteBufferStream.new(socket)
    stream = Riser::LoggingStream.new(stream, stdout_log)

    stdout_log.info("connect from #{socket.remote_address.inspect_sockaddr}")
    catch(:end_of_connection) {
      while (true)
        until (read_poll.call(1))
          if (read_poll.interval_seconds >= 10) then
            throw(:end_of_connection)
          end
        end

        line = stream.gets or throw(:end_of_connection)
        stream.write(line)
        stream.flush
      end
    }
    stream.close
  rescue
    stdout_log.error($!)
  end
}

server.start(socket_address.open_server)

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
