#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

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

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
