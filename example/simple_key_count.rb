#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'pstore'
require 'riser'

Riser::Daemon.start_daemon(daemonize: false,
                           daemon_name: 'simple_key_count',
                           listen_address: 'localhost:8000'
                          ) {|server|

  services = Riser::DRbServices.new(4)
  services.add_sticky_process_service(:pstore,
                                      Riser::ResourceSet.build{|builder|
                                        builder.at_create{|key|
                                          PStore.new("simple_key_count-#{key}.pstore", true)
                                        }
                                        builder.at_destroy{|pstore|
                                          # nothing to do about `pstore'.
                                        }
                                      })

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

        _path, query = uri.split('?', 2)
        key = query || 'default'
        services.call_service(:pstore, key) {|pstore|
          pstore.transaction do
            pstore[:count] ||= 0
            pstore[:count] += 1
            socket << 'key: ' << key << "\n"
            socket << 'count: ' << pstore[:count] << "\n"
          end
        }
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
