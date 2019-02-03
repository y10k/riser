#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

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

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
