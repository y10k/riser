#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'logger'
require 'pathname'
require 'riser'

base_dir = Pathname(File.dirname($0))

Riser::Daemon.start_daemon(daemonize: true,
                           daemon_name: 'simple_daemon',
                           status_file: (base_dir + 'simple_daemon.pid').to_s,
                           listen_address: 'localhost:5000'
                          ) {|server|

  logger = Logger.new((base_dir + 'simple_daemon.log').to_s)
  server.dispatch{|socket|
    stream = Riser::LoggingStream.new(socket, logger)
    while (line = stream.gets)
      stream.write(line)
    end
  }
}

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
