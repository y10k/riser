#!/usr/local/bin/ruby
# -*- coding: utf-8 -*-

require 'logger'
require 'pp'
require 'riser'
require 'socket'
require 'time'

host = ARGV.shift || 'localhost'
port = Integer(ARGV.shift || '8080')

server = Riser::SocketServer.new
server.process_num = 4

Signal.trap('TERM') { server.signal_stop_graceful }
Signal.trap('INT') { server.signal_stop_forced }
Signal.trap('QUIT') { server.signal_stop_forced }
Signal.trap('USR1') { server.signal_stat_get(reset: true) }
Signal.trap('USR2') { server.signal_stat_get(reset: false) }
Signal.trap('WINCH') { server.signal_stat_stop }

server.at_fork{ puts "fork: #{Process.ppid} -> #{Process.pid}" }
server.at_stop{|state| puts "stop: #{state} (pid: #{Process.pid})" }
server.at_stat{|info| puts info.pretty_inspect }
server.preprocess{ puts "preprocess (pid: #{Process.pid})" }
server.postprocess{ puts "postprocess (pid: #{Process.pid})" }

HALO = IO.read(File.join(File.dirname(__FILE__),
                         File.basename(__FILE__, '.rb') + '.html'))

stdout_log = Logger.new(STDOUT)
protocol_log = Logger.new(File.join(File.dirname(__FILE__), 'protocol.log'))

server.dispatch{|socket|
  begin
    read_poll = Riser::ReadPoll.new(socket)
    stream = Riser::WriteBufferStream.new(socket)
    stream = Riser::LoggingStream.new(stream, protocol_log)

    catch(:end_of_connection) {
      count = 0
      while (count < 100)
        count += 1

        until (read_poll.call(1))
          if (read_poll.interval_seconds >= 10) then
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
  rescue
    stdout_log.error($!)
  end
}

socket = TCPServer.new(host, port)
server.start(socket)

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
