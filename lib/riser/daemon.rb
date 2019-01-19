# -*- coding: utf-8 -*-

module Riser
  class RootProcess
    class SystemOperation
      def initialize(logger)
        @logger = logger
      end

      def get_server_address(sockaddr_get)
        begin
          address_config = sockaddr_get.call
        rescue
          @logger.error("failed to get server address [#{$!}]")
          @logger.debug($!) if @logger.debug?
          return
        end

        server_address = SocketAddress.parse(address_config)
        unless (server_address) then
          @logger.error("failed to parse server address: #{address_config.inspect}")
        end
        server_address
      end
    end

    include ServerSignal

    def initialize(logger, sockaddr_get, server_watch_interval_seconds, &block)
      @logger = logger
      @sockaddr_get = sockaddr_get
      @server_watch_interval_seconds = server_watch_interval_seconds
      @server_setup = block
      @stop_state = nil
      @signal_operation_queue = []
    end

    # should be called from signal(2) handler
    def signal_stop_graceful
      @stop_state ||= :graceful
      nil
    end

    # should be called from signal(2) handler
    def signal_stop_forced
      @stop_state ||= :forced
      nil
    end

    # should be called from signal(2) handler
    def signal_restart_graceful
      @signal_operation_queue << :restart_graceful
      nil
    end

    # should be called from signal(2) handler
    def signal_restart_forced
      @signal_operation_queue << :restart_forced
      nil
    end

    # should be called from signal(2) handler
    def signal_stat_get(reset: true)
      if (reset) then
        @signal_operation_queue << :stat_get_and_reset
      else
        @signal_operation_queue << :stat_get_no_reset
      end
      nil
    end

    # should be called from signal(2) handler
    def signal_stat_stop
      @signal_operation_queue << :stat_stop
      nil
    end

    def get_server_address
      begin
        address_config = @sockaddr_get.call
      rescue
        @logger.error("failed to get server address [#{$!}]")
        @logger.debug($!) if @logger.debug?
        return
      end

      server_address = SocketAddress.parse(address_config)
      unless (server_address) then
        @logger.error("failed to parse server address: #{address_config.inspect}")
      end
      server_address
    end
    private :get_server_address

    def get_server_socket(server_address)
      begin
        server_address.open_server
      rescue
        @logger.error("failed to open server socket: #{server_address.inspect} [#{$!}]")
        @logger.debug($!) if @logger.debug?
        nil
      end
    end
    private :get_server_socket

    def server_send_signal(pid, signal, error_message)
      begin
        Process.kill(signal, pid)
      rescue
        @logger.error("#{error_message} [#{$!}]")
        @logger.debug($!) if @logger.debug?
        nil
      end
    end
    private :server_send_signal

    def server_stop_graceful(pid)
      server_send_signal(pid, SIGNAL_STOP_GRACEFUL, "server graceful stop error (pid: #{pid})")
    end
    private :server_stop_graceful

    def server_stop_forced(pid)
      server_send_signal(pid, SIGNAL_STOP_FORCED, "server forced stop error (pid: #{pid})")
    end
    private :server_stop_forced

    def server_stop_wait(pid, flags=0)
      begin
        Process.wait(pid, flags)
      rescue
        @logger.error("server wait(2) error (pid: #{pid}) [#{$!}]")
        @logger.debug($!) if @logger.debug?
        nil
      end
    end
    private :server_stop_wait

    def run_server(server_socket)
      begin
        latch_read_io, latch_write_io = IO.pipe
      rescue
        @logger.error("failed to pipe(2) [#{$!}]")
        @logger.debug($!) if @logger.debug?
        return
      end

      begin
        pid = Process.fork{
          @logger.close
          latch_read_io.close

          server = SocketServer.new
          Signal.trap(SIGNAL_STOP_GRACEFUL) { server.signal_stop_graceful }
          Signal.trap(SIGNAL_STOP_FORCED) { server.signal_stop_forced }
          Signal.trap(SIGNAL_STAT_GET_AND_RESET) { server.signal_stat_get(reset: true) }
          Signal.trap(SIGNAL_STAT_GET_NO_RESET) { server.signal_stat_get(reset: false) }
          Signal.trap(SIGNAL_STAT_STOP) { server.signal_stat_stop }
          @server_setup.call(server)
          latch_write_io.puts("server process (pid: #{$$}) is ready to go.")

          server.start(server_socket)
        }
      rescue
        @logger.error("failed to fork(2) server process [#{$!}]")
        @logger.debug($!) if @logger.debug?
        for io in [ latch_read_io, latch_write_io ]
          begin
            io.close
          rescue
            @logger.error("failed to close pipe(2) [#{$!}]")
            @logger.debug($!) if @logger.debug?
          end
        end
        return
      end

      begin
        begin
          latch_write_io.close
          if (s = latch_read_io.gets) then
            @logger.debug("[server process message] #{s.chomp}") if @logger.debug?
          else
            @logger.error("no response from server process (pid: #{pid})")
            server_send_signal(pid, SIGNAL_STOP_FORCED, "failed to kill abnormal server process (pid: #{pid})")
            server_stop_wait(pid)
            return
          end
        ensure
          latch_read_io.close
        end
      rescue
        @logger.error("unexpected error [#{$!}]")
        @logger.debug($!) if @logger.debug?
        if (server_send_signal(pid, SIGNAL_STOP_FORCED, "failed to kill abnormal server process (pid: #{pid})")) then
          server_stop_wait(pid)
        end
        return
      end

      pid
    end
    private :run_server

    # should be executed on the main thread sharing the stack with
    # signal(2) handlers
    def start
      @logger.info('daemon start.')

      unless (server_address = get_server_address) then
        @logger.fatal('failed to start daemon.')
        return 1
      end

      unless (server_socket = get_server_socket(server_address)) then
        @logger.fatal('failed to start daemon.')
        return 1
      end
      @logger.info("open server socket: #{server_socket.local_address.inspect_sockaddr}")

      unless (pid = run_server(server_socket)) then
        @logger.fatal('failed to start daemon.')
        return 1
      end
      @logger.info("server process start (pid: #{pid})")

      until (@stop_state)
        sleep(@server_watch_interval_seconds)

        if (! pid || server_stop_wait(pid, Process::WNOHANG)) then
          if (pid) then
            @logger.warn("found server down (pid: #{pid}) and restart server.")
          else
            @logger.warn('found server down and restart server.')
          end
          if (pid = run_server(server_socket)) then
            @logger.info("server process start (pid: #{pid})")
          end
        end

        catch(:end_of_signal_operation) {
          while (sig_ope = @signal_operation_queue.shift)
            case (sig_ope)
            when :restart_graceful, :restart_forced
              if (next_server_address = get_server_address) then
                if (next_server_address != server_address) then
                  if (next_server_socket = get_server_socket(next_server_address)) then
                    @logger.info("open server socket: #{next_server_socket.local_address.inspect_sockaddr}")
                    begin
                      @logger.info("close server socket: #{server_socket.local_address.inspect_sockaddr}")
                      server_socket.close
                    rescue
                      @logger.warn("failed to close server socket (#{server_address.inspect}) [#{$!}]")
                      @logger.debug($!) if @logger.debug?
                    end
                    server_socket = next_server_socket
                    server_address = next_server_address
                  else
                    @logger.warn("server socket continue: #{server_socket.local_address.inspect_sockaddr}")
                  end
                end
              else
                @logger.warn("server socket continue: #{server_socket.local_address.inspect_sockaddr}")
              end

              case (sig_ope)
              when :restart_graceful
                @logger.info("server graceful restart (pid: #{pid})")
                server_stop_graceful(pid)
              when :restart_forced
                @logger.info("server forced restart (pid: #{pid})")
                server_stop_forced(pid)
              else
                @logger.warn("internal warning: unknown signal operation <#{sig_ope.inspect}>")
              end

              if (next_pid = run_server(server_socket)) then
                @logger.info("server process start (pid: #{next_pid})")
                server_stop_wait(pid)
                @logger.info("server stop completed (pid: #{pid})")
                pid = next_pid
              else
                # If the server fails to start, retry to start server in the next loop.
                throw(:end_of_signal_operation)
              end
            when :stat_get_and_reset
              @logger.info("stat get(reset: true) (pid: #{pid})")
              server_send_signal(pid, SIGNAL_STAT_GET_AND_RESET, "failed to stat get(reset: true) (pid: #{pid})")
            when :stat_get_no_reset
              @logger.info("stat get(reset: false) (pid: #{pid})")
              server_send_signal(pid, SIGNAL_STAT_GET_NO_RESET, "failed to stat get(reset: false) (pid: #{pid})")
            when :stat_stop
              @logger.info("stat stop (pid: #{pid})")
              server_send_signal(pid, SIGNAL_STAT_STOP, "failed to stat stop (pid: #{pid})")
            else
              @logger.warn("internal warning: unknown signal operation <#{sig_ope.inspect}>")
            end
          end
        }
      end

      case (@stop_state)
      when :graceful
        @logger.info("server graceful stop (pid: #{pid})")
        unless (server_stop_graceful(pid)) then
          @logger.fatal('failed to stop daemon.')
          return 1
        end
        unless (server_stop_wait(pid)) then
          @logger.fatal('failed to stop daemon.')
          return 1
        end
      when :forced
        @logger.info("server forced stop (pid: #{pid})")
        unless (server_stop_forced(pid)) then
          @logger.fatal('failed to stop daemon.')
          return 1
        end
        unless (server_stop_wait(pid)) then
          @logger.fatal('failed to stop daemon.')
          return 1
        end
      else
        @logger.error("internal error: unknown stop state <#{@stop_state.inspect}>")
        return 1
      end

      @logger.info('daemon stop.')
      return 0
    end
  end

  module Daemon
    include ServerSignal
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
