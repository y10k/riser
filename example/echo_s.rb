#!/usr/local/bin/ruby
# -*- coding: utf-8 -*-

require 'logger'
require 'openssl'
require 'riser'
require 'socket'

cert_path = ARGV.shift or raise 'need for server certificate file'
pkey_path = ARGV.shift or raise 'need for server private key file'
host = ARGV.shift || 'localhost'
port = Integer(ARGV.shift || '50443')

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

stdout_log = Logger.new(STDOUT)

ssl_context = OpenSSL::SSL::SSLContext.new
ssl_context.cert = OpenSSL::X509::Certificate.new(File.read(cert_path))
ssl_context.key = OpenSSL::PKey::RSA.new(File.read(pkey_path))

server.dispatch{|socket|
  begin
    ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, ssl_context)
    ssl_socket.accept

    read_poll = Riser::ReadPoll.new(socket)
    # SSLSocket is buffered and no need for WriteBufferStream
    stream = Riser::LoggingStream.new(ssl_socket, stdout_log)

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

socket = TCPServer.new(host, port)
server.start(socket)

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
