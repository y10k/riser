#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

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

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
