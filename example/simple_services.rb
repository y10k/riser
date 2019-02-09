#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'riser'

Riser::Daemon.start_daemon(daemonize: false,
                           daemon_name: 'simple_services',
                           listen_address: 'localhost:8000'
                          ) {|server|

  services = Riser::DRbServices.new(4)
  services.add_any_process_service(:pid_any, proc{ $$ })
  services.add_single_process_service(:pid_single, proc{ $$ })
  services.add_sticky_process_service(:pid_stickty, proc{|key| $$ })

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
      method, uri, _version = line.split
      while (line = socket.gets)
        line.strip.empty? and break
      end
      if (method == 'GET') then
        socket << "HTTP/1.0 200 OK\r\n"
        socket << "Content-Type: text/plain\r\n"
        socket << "\r\n"

        path, query = uri.split('?', 2)
        case (path)
        when '/any'
          socket << 'pid: ' << services.call_service(:pid_any) << "\n"
        when '/single'
          socket << 'pid: ' << services.call_service(:pid_single) << "\n"
        when '/sticky'
          key = query || 'default'
          socket << 'key: ' << key << "\n"
          socket << 'pid: ' << services.call_service(:pid_stickty, key) << "\n"
        else
          socket << "unknown path: #{path}\n"
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
