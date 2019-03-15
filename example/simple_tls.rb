#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

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

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
