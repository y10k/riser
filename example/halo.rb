#!/usr/local/bin/ruby
# -*- coding: utf-8 -*-

require 'logger'
require 'pp'
require 'riser'
require 'socket'
require 'thread'
require 'time'

class ConnectionLimits
  def initialize(max_count, request_timeout_seconds)
    @mutex = Mutex.new
    self.max_count = max_count
    self.request_timeout_seconds = request_timeout_seconds
  end

  def max_count
    @mutex.synchronize{ @max_count }
  end

  def max_count=(value)
    @mutex.synchronize{ @max_count = value }
  end

  def request_timeout_seconds
    @mutex.synchronize{ @request_timeout_seconds }
  end

  def request_timeout_seconds=(value)
    @mutex.synchronize{ @request_timeout_seconds = value }
  end
end

socket_config = ARGV.shift || 'localhost:8080'
socket_address = Riser::SocketAddress.parse(socket_config)

server = Riser::SocketServer.new
server.process_num = 4

Signal.trap('TERM') { server.signal_stop_graceful }
Signal.trap('INT') { server.signal_stop_forced }
Signal.trap('QUIT') { server.signal_stop_forced }
Signal.trap('USR1') { server.signal_stat_get(reset: true) }
Signal.trap('USR2') { server.signal_stat_get(reset: false) }
Signal.trap('WINCH') { server.signal_stat_stop }

conn_limits = ConnectionLimits.new(100, 10)
server.before_start{|server_socket|
  puts "before start (pid: #{Process.pid})"
  puts "listen #{server_socket.local_address.inspect_sockaddr}"
}
server.at_fork{ puts "fork: #{Process.ppid} -> #{Process.pid}" }
server.at_stop{|state|
  puts "stop: #{state} (pid: #{Process.pid})"
  conn_limits.max_count = 1
  conn_limits.request_timeout_seconds = 0
}
server.at_stat{|info| puts info.pretty_inspect }
server.preprocess{ puts "preprocess (pid: #{Process.pid})" }
server.postprocess{ puts "postprocess (pid: #{Process.pid})" }
server.after_stop{ puts "after stop (pid: #{Process.pid})" }

HALO = IO.read(File.join(File.dirname(__FILE__),
                         File.basename(__FILE__, '.rb') + '.html'))

stdout_log = Logger.new(STDOUT)
protocol_log = Logger.new(File.join(File.dirname(__FILE__), 'protocol.log'))

server.dispatch{|socket|
  begin
    read_poll = Riser::ReadPoll.new(socket)
    stream = Riser::WriteBufferStream.new(socket)
    stream = Riser::LoggingStream.new(stream, protocol_log)

    stdout_log.info("connect from #{socket.remote_address.inspect_sockaddr}")
    catch(:end_of_connection) {
      count = 0
      while (count < conn_limits.max_count)
        count += 1

        until (read_poll.call(1))
          if (read_poll.interval_seconds >= conn_limits.request_timeout_seconds) then
            throw(:end_of_connection)
          end
        end

        begin
          if (request_line = stream.gets) then
            if (request_line =~ %r"\A (\S+) \s (\S+) \s (HTTP/\S+) \r\n \z"x) then
              method, path, version = $1, $2, $3
              while (line = stream.gets)
                if (line == "\r\n") then
                  break
                end
              end
              stdout_log.info("#{method} #{path} #{version}")

              t = Time.now
              case (method)
              when 'GET'
                stream << "HTTP/1.0 200 OK\r\n"
                stream << "Content-Type: text/html\r\n"
                stream << "Content-Length: #{HALO.bytesize}\r\n"
                stream << "Date: #{t.httpdate}\r\n"
                stream << "\r\n"
                stream << HALO
              else
                stream << "HTTP/1.0 405 Method Not Allowed\r\n"
                stream << "Content-Type: text/plain\r\n"
                stream << "Date: #{t.httpdate}\r\n"
                stream << "\r\n"
                stream << "#{method} is not allowed.\r\n"
                throw(:end_of_connection)
              end
            end
          end
        ensure
          stream.flush
        end
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
