#!/usr/local/bin/ruby
# -*- coding: utf-8 -*-

require 'logger'
require 'openssl'
require 'riser'
require 'socket'
require 'thread'

class ConnectionLimits
  def initialize(request_max_count, request_timeout_seconds)
    @mutex = Mutex.new
    self.request_max_count = request_max_count
    self.request_timeout_seconds = request_timeout_seconds
  end

  def request_max_count
    @mutex.synchronize{ @request_max_count }
  end

  def request_max_count=(value)
    @mutex.synchronize{ @request_max_count = value }
  end

  def request_timeout_seconds
    @mutex.synchronize{ @request_timeout_seconds }
  end

  def request_timeout_seconds=(value)
    @mutex.synchronize{ @request_timeout_seconds = value }
  end
end

cert_path = ARGV.shift or raise 'need for server certificate file'
pkey_path = ARGV.shift or raise 'need for server private key file'
socket_config = ARGV.shift || 'localhost:50443'
socket_address = Riser::SocketAddress.parse(socket_config)

server = Riser::SocketServer.new
server.process_num = 4

Signal.trap('TERM') { server.signal_stop_graceful }
Signal.trap('INT') { server.signal_stop_forced }
Signal.trap('QUIT') { server.signal_stop_forced }
Signal.trap('USR1') { server.signal_stat_get(reset: true) }
Signal.trap('USR2') { server.signal_stat_get(reset: false) }
Signal.trap('WINCH') { server.signal_stat_stop }

stdout_log = Logger.new(STDOUT)

server.before_start{|server_socket|
  stdout_log.info("start echo TLS server: listen #{server_socket.local_address.inspect_sockaddr}")
}
server.after_stop{
  stdout_log.info('stop server')
}
server.at_stat{|info|
  stdout_log.info("stat: #{info.pretty_inspect}")
}

conn_limits = ConnectionLimits.new(100, 10)
server.at_stop{|state|
  stdout_log.info("at stop: #{state}")
  conn_limits.request_max_count = 1
  conn_limits.request_timeout_seconds = 0
}

server.at_fork{ stdout_log.info('at fork') }
server.preprocess{ stdout_log.info('preprocess') }
server.postprocess{ stdout_log.info('postprocess') }

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

    stdout_log.info("connect from #{socket.remote_address.inspect_sockaddr}")
    catch(:end_of_connection) {
      count = 0
      while (count < conn_limits.request_max_count)
        count += 1

        until (read_poll.call(1))
          if (read_poll.interval_seconds >= conn_limits.request_timeout_seconds) then
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
