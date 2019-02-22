#!/usr/local/bin/ruby
# -*- coding: utf-8 -*-

require 'logger'
require 'optparse'
require 'pp'
require 'riser'
require 'time'
require 'yaml'

class ConnectionLimits
  def initialize(request_max_count, request_timeout_seconds)
    @mutex = Thread::Mutex.new
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

options = {
  daemonize: false,
  debug: false
}

OptionParser.new{|opts|
  opts.banner = "Usage: #{File.basename($0)} [options]"
  opts.on('-d', '--[no-]daemonize', 'Run as daemon') do |value|
    options[:daemonize] = value
  end
  opts.on('-g', '--[no-]debug', 'Run debug') do |value|
    options[:debug] = value
  end
}.parse!

name = File.basename($0, '.rb')
server_log   = File.join(File.dirname($0), "#{name}.log")
protocol_log = File.join(File.dirname($0), 'protocol.log')
status_file  = File.join(File.dirname($0), "#{name}.pid")
config_path  = File.join(File.dirname($0), "#{name}.yml")
halo_html    = File.join(File.dirname($0), "#{name}.html")

config = YAML.load_file(config_path)['daemon']

Riser::Daemon.start_daemon(daemonize: options[:daemonize],
                           daemon_name: name,
                           daemon_debug: options[:debug],
                           status_file: status_file,
                           listen_address: proc{
                             # to reload on server restart
                             YAML.load_file(config_path).dig('server', 'server_listen')
                           },
                           server_polling_interval_seconds: config['server_polling_interval_seconds'],
                           server_restart_overlap_seconds:  config['server_restart_overlap_seconds'],
                           server_privileged_user:          config['server_privileged_user'],
                           server_privileged_group:         config['server_privileged_group']
                          ) {|server|

  c = YAML.load_file(config_path)['server']

  logger = Logger.new(server_log)
  logger.level = c['server_log_level']
  p_logger = Logger.new(protocol_log)
  p_logger.level = c['protocol_log_level']

  server.accept_polling_timeout_seconds          = c['accept_polling_timeout_seconds']
  server.process_num                             = c['process_num']
  server.process_queue_size                      = c['process_queue_size']
  server.process_queue_polling_timeout_seconds   = c['process_queue_polling_timeout_seconds']
  server.process_send_io_polling_timeout_seconds = c['process_send_io_polling_timeout_seconds']
  server.thread_num                              = c['thread_num']
  server.thread_queue_size                       = c['thread_queue_size']
  server.thread_queue_polling_timeout_seconds    = c['thread_queue_polling_timeout_seconds']

  server.before_start{|socket|
    logger.info("start HTTP server: listen #{socket.local_address.inspect_sockaddr}")
  }
  server.after_stop{
    logger.info('stop server')
  }
  server.at_stat{|info|
    logger.info("stat: #{info.pretty_inspect}")
  }

  conn_limits = ConnectionLimits.new(c['request_max_count'], c['request_timeout_seconds'])
  server.at_stop{|state|
    logger.info("at stop: #{state}")
    conn_limits.request_max_count = 1
    conn_limits.request_timeout_seconds = 0
  }

  server.at_fork{ logger.info('at fork') }
  server.preprocess{ logger.info('preprocess') }
  server.postprocess{ logger.info('postprocess') }

  halo = File.read(halo_html)

  server.dispatch{|socket|
    begin
      read_poll = Riser::ReadPoll.new(socket)
      stream = Riser::WriteBufferStream.new(socket)
      stream = Riser::LoggingStream.new(stream, p_logger)

      logger.info("connect from #{socket.remote_address.inspect_sockaddr}")
      catch(:end_of_connection) {
        count = 0
        while (count < conn_limits.request_max_count)
          count += 1

          until (read_poll.call(1))
            if (read_poll.interval_seconds >= conn_limits.request_timeout_seconds) then
              throw(:end_of_connection)
            end
          end

          request_line = stream.gets or throw(:end_of_connection)
          request_line =~ %r"\A (\S+) \s (\S+) \s (HTTP/\S+) \r\n \z"x or throw(:end_of_connection)
          method, path, version = $1, $2, $3
          while (line = stream.gets)
            if (line == "\r\n") then
              break
            end
          end
          logger.info("#{method} #{path} #{version}")

          begin
            t = Time.now
            case (method)
            when 'GET', 'HEAD'
              stream << "HTTP/1.0 200 OK\r\n"
              stream << "Content-Type: text/html\r\n"
              stream << "Content-Length: #{halo.bytesize}\r\n"
              stream << "Date: #{t.httpdate}\r\n"
              stream << "\r\n"
              stream << halo if (method == 'GET')
            else
              stream << "HTTP/1.0 405 Method Not Allowed\r\n"
              stream << "Content-Type: text/plain\r\n"
              stream << "Date: #{t.httpdate}\r\n"
              stream << "\r\n"
              stream << "#{method} is not allowed.\r\n"
              throw(:end_of_connection)
            end
          ensure
            stream.flush
          end
        end
      }
      stream.close
    rescue
      logger.error($!)
    end
  }
}

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
