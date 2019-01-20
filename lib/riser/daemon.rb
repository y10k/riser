# -*- coding: utf-8 -*-

module Riser
  class RootProcess
    class SystemOperation
      def initialize(logger, module_Process: Process, class_IO: IO)
        @logger = logger
        @Process = module_Process
        @IO = class_IO
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

      def get_server_socket(server_address)
        begin
          server_address.open_server
        rescue
          @logger.error("failed to open server socket: #{server_address} [#{$!}]")
          @logger.debug($!) if @logger.debug?
          nil
        end
      end

      def send_signal(pid, signal)
        begin
          @Process.kill(signal, pid)
        rescue
          @logger.error("failed to send signal (#{signal}) to process (pid: #{pid}) [#{$!}]")
          @logger.debug($!) if @logger.debug?
          nil
        end
      end

      def wait(pid, flags=0)
        begin
          @Process.wait(pid, flags)
        rescue
          @logger.error("failed to wait(2) for process (pid: #{pid}) [#{$!}]")
          @logger.debug($!) if @logger.debug?
          nil
        end
      end

      def pipe
        begin
          @IO.pipe
        rescue
          @logger.error("failed to pipe(2) [#{$!}]")
          @logger.debug($!) if @logger.debug?
          nil
        end
      end

      def fork
        begin
          @Process.fork{ yield }
        rescue
          @logger.error("failed to fork(2) [#{$!}]")
          @logger.debug($!) if @logger.debug?
          nil
        end
      end

      def gets(io)
        begin
          io.gets
        rescue
          @logger.error("failed to get line from #{io.inspect} [#{$!}]")
          @logger.debug($!) if @logger.debug?
          nil
        end
      end

      def close(io)
        begin
          io.close
          io
        rescue
          @logger.error("failed to close(2) #{io.inspect} [#{$!}]")
          @logger.debug($!) if @logger.debug?
          nil
        end
      end
    end

    include ServerSignal

    def initialize(logger, sockaddr_get, server_polling_interval_seconds, &block) # :yields: socket_server
      @logger = logger
      @sockaddr_get = sockaddr_get
      @server_polling_interval_seconds = server_polling_interval_seconds
      @server_setup = block
      @sysop = SystemOperation.new(@logger)
      @stop_state = nil
      @signal_operation_queue = []
      @process_wait_count_table = {}
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

    def server_stop_graceful(pid)
      ret_val = @sysop.send_signal(pid, SIGNAL_STOP_GRACEFUL)
      unless (ret_val) then
        @logger.error("server graceful stop error (pid: #{pid})")
      end
      ret_val
    end
    private :server_stop_graceful

    def server_stop_forced(pid)
      ret_val = @sysop.send_signal(pid, SIGNAL_STOP_FORCED)
      unless (ret_val) then
        @logger.error("server forced stop error (pid: #{pid})")
      end
      ret_val
    end
    private :server_stop_forced

    def run_server(server_socket)
      read_write = @sysop.pipe
      unless (read_write) then
        @logger.error('failed to start server.')
        return
      end
      latch_read_io, latch_write_io = read_write

      pid = @sysop.fork{
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

      unless (pid) then
        @sysop.close(latch_read_io)
        @sysop.close(latch_write_io)
        @logger.error('failed to start server.')
        return
      end

      error_count = 0
      @sysop.close(latch_write_io) or error_count += 1
      server_messg = @sysop.gets(latch_read_io)
      @sysop.close(latch_read_io) or error_count += 1

      if (server_messg) then
        @logger.debug("[server process message] #{server_messg.chomp}") if @logger.debug?
      else
        @logger.error("no response from server process (pid: #{pid})")
      end

      if (! server_messg || error_count > 0) then
        @sysop.send_signal(pid, SIGNAL_STOP_FORCED) or @logger.error("failed to kill abnormal server process (pid: #{pid})")
        @process_wait_count_table[pid] = 0
        @logger.error('failed to start server.')
        return
      end

      pid
    end
    private :run_server

    # should be executed on the main thread sharing the stack with
    # signal(2) handlers
    def start
      @logger.info('daemon start.')

      unless (server_address = @sysop.get_server_address(@sockaddr_get)) then
        @logger.fatal('failed to start daemon.')
        return 1
      end

      unless (server_socket = @sysop.get_server_socket(server_address)) then
        @logger.fatal('failed to start daemon.')
        return 1
      end
      @logger.info("open server socket: #{server_socket.local_address.inspect_sockaddr}")

      unless (server_pid = run_server(server_socket)) then
        @logger.fatal('failed to start daemon.')
        return 1
      end
      @logger.info("server process start (pid: #{server_pid})")

      until (@stop_state)
        sleep(@server_polling_interval_seconds)

        if (! server_pid || @sysop.wait(server_pid, Process::WNOHANG)) then
          if (server_pid) then
            @logger.warn("found server down (pid: #{server_pid}) and restart server.")
          else
            @logger.warn('found server down and restart server.')
          end
          if (server_pid = run_server(server_socket)) then
            @logger.info("server process start (pid: #{server_pid})")
          end
        end

        catch(:end_of_signal_operation) {
          while (sig_ope = @signal_operation_queue.shift)
            case (sig_ope)
            when :restart_graceful, :restart_forced
              if (next_server_address = @sysop.get_server_address(@sockaddr_get)) then
                if (next_server_address != server_address) then
                  if (next_server_socket = @sysop.get_server_socket(next_server_address)) then
                    @logger.info("open server socket: #{next_server_socket.local_address.inspect_sockaddr}")
                    @logger.info("close server socket: #{server_socket.local_address.inspect_sockaddr}")
                    @sysop.close(server_socket) or @logger.warn("failed to close server socket (#{server_address})")
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
                @logger.info("server graceful restart (pid: #{server_pid})")
                server_stop_graceful(server_pid)
              when :restart_forced
                @logger.info("server forced restart (pid: #{server_pid})")
                server_stop_forced(server_pid)
              else
                @logger.warn("internal warning: unknown signal operation <#{sig_ope.inspect}>")
              end

              if (next_pid = run_server(server_socket)) then
                @logger.info("server process start (pid: #{next_pid})")
                @process_wait_count_table[server_pid] = 0
                server_pid = next_pid
              else
                # If the server fails to start, retry to start server in the next loop.
                throw(:end_of_signal_operation)
              end
            when :stat_get_and_reset
              @logger.info("stat get(reset: true) (pid: #{server_pid})")
              @sysop.send_signal(server_pid, SIGNAL_STAT_GET_AND_RESET) or @logger.error("failed to stat get(reset: true) (pid: #{server_pid})")
            when :stat_get_no_reset
              @logger.info("stat get(reset: false) (pid: #{server_pid})")
              @sysop.send_signal(server_pid, SIGNAL_STAT_GET_NO_RESET) or @logger.error("failed to stat get(reset: false) (pid: #{server_pid})")
            when :stat_stop
              @logger.info("stat stop (pid: #{server_pid})")
              @sysop.send_signal(server_pid, SIGNAL_STAT_STOP) or @logger.error("failed to stat stop (pid: #{server_pid})")
            else
              @logger.warn("internal warning: unknown signal operation <#{sig_ope.inspect}>")
            end
          end
        }

        for pid in @process_wait_count_table.keys
          if (@sysop.wait(pid, Process::WNOHANG)) then
            @logger.info("server stop completed (pid: #{pid})")
            @process_wait_count_table.delete(pid)
          else
            @process_wait_count_table[pid] += 1
            if (@process_wait_count_table[pid] >= 2) then
              @logger.warn("not stopped server process (pid: #{pid})")
            end
          end
        end
      end

      case (@stop_state)
      when :graceful
        @logger.info("server graceful stop (pid: #{server_pid})")
        unless (server_stop_graceful(server_pid)) then
          @logger.fatal('failed to stop daemon.')
          return 1
        end
        unless (@sysop.wait(server_pid)) then
          @logger.fatal('failed to stop daemon.')
          return 1
        end
      when :forced
        @logger.info("server forced stop (pid: #{server_pid})")
        unless (server_stop_forced(server_pid)) then
          @logger.fatal('failed to stop daemon.')
          return 1
        end
        unless (@sysop.wait(server_pid)) then
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
