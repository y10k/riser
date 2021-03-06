# -*- coding: utf-8 -*-

require 'fileutils'
require 'logger'
require 'syslog/logger'
require 'yaml'

module Riser
  class StatusFile
    def initialize(filename)
      @filename = filename
    end

    def open
      @file = File.open(@filename, File::WRONLY | File::CREAT, 0644)
      self
    end

    def close
      @file.close
      nil
    end

    def lock
      @file.flock(File::LOCK_EX | File::LOCK_NB)
    end

    def self.locked?(status_file_path)
      begin
        File.open(status_file_path, File::WRONLY) {|lock_file|
          ! lock_file.flock(File::LOCK_EX | File::LOCK_NB)
        }
      rescue Errno::ENOENT
        false
      end
    end

    def write(text)
      @file.truncate(0)
      @file.seek(0)
      ret_val = @file.write(text)
      @file.flush
      ret_val
    end
  end

  class SystemOperation
    def initialize(logger, module_FileUtils: FileUtils, module_Process: Process, class_IO: IO, class_File: File)
      @logger = logger
      @FileUtils = module_FileUtils
      @Process = module_Process
      @IO = class_IO
      @File = class_File
    end

    def get_server_address(sockaddr_get)
      begin
        address_config = sockaddr_get.call
      rescue
        @logger.error("failed to get server address [#{$!} (#{$!.class})]")
        @logger.debug($!) if @logger.debug?
        return
      end

      begin
        server_address = SocketAddress.parse(address_config)
      rescue
        @logger.error("failed to parse server address: #{address_config.inspect} [#{$!} (#{$!.class})]")
        @logger.debug($!) if @logger.debug?
        return
      end

      server_address
    end

    def get_server_socket(server_address)
      begin
        server_address.open_server
      rescue
        @logger.error("failed to open server socket: #{server_address} [#{$!} (#{$!.class})]")
        @logger.debug($!) if @logger.debug?
        nil
      end
    end

    def get_sockaddr(server_socket)
      begin
        server_socket.local_address.inspect_sockaddr
      rescue
        @logger.error("failed to get socket address: #{server_socket} [#{$!} (#{$!.class})]")
        @logger.debug($!) if @logger.debug?
        nil
      end
    end

    def listen(server_socket, backlog)
      begin
        server_socket.listen(backlog)
      rescue
        @logger.error("failed to listen(2) server socket with backlog: #{backlog} [#{$!} (#{$!.class})]")
        @logger.debug($!) if @logger.debug?
        nil
      end
    end

    def chmod(mode, path)
      begin
        @FileUtils.chmod(mode, path)
      rescue
        @logger.error("failed to chmod(2): #{'%04o' % mode} #{path} [#{$!} (#{$!.class})]")
        @logger.debug($!) if @logger.debug?
        nil
      end
    end

    def chown(owner, group, path)
      begin
        @FileUtils.chown(owner, group, path)
      rescue
        @logger.error("failed to chown(2): <#{owner}> <#{group}> <#{path}> [#{$!} (#{$!.class})]")
        @logger.debug($!) if @logger.debug?
        nil
      end
    end

    def send_signal(pid, signal)
      begin
        @Process.kill(signal, pid)
      rescue
        @logger.error("failed to send signal (#{signal}) to process (pid: #{pid}) [#{$!} (#{$!.class})]")
        @logger.debug($!) if @logger.debug?
        nil
      end
    end

    def wait(pid, flags=0)
      begin
        @Process.wait(pid, flags)
      rescue
        @logger.error("failed to wait(2) for process (pid: #{pid}) [#{$!} (#{$!.class})]")
        @logger.debug($!) if @logger.debug?
        nil
      end
    end

    def pipe
      begin
        @IO.pipe
      rescue
        @logger.error("failed to pipe(2) [#{$!} (#{$!.class})]")
        @logger.debug($!) if @logger.debug?
        nil
      end
    end

    def fork
      begin
        @Process.fork{ yield }
      rescue
        @logger.error("failed to fork(2) [#{$!} (#{$!.class})]")
        @logger.debug($!) if @logger.debug?
        nil
      end
    end

    def gets(io)
      begin
        io.gets
      rescue
        @logger.error("failed to get line from #{io.inspect} [#{$!} (#{$!.class})]")
        @logger.debug($!) if @logger.debug?
        nil
      end
    end

    def close(io)
      begin
        io.close
        io
      rescue
        @logger.error("failed to close(2) #{io.inspect} [#{$!} (#{$!.class})]")
        @logger.debug($!) if @logger.debug?
        nil
      end
    end

    def unlink(path)
      begin
        File.unlink(path)
      rescue
        @logger.error("failed to unlink(2): #{path} [#{$!} (#{$!.class})]")
        @logger.debug($!) if @logger.debug?
        nil
      end
    end
  end

  class RootProcess
    include ServerSignal

    def initialize(logger, sockaddr_get, server_polling_interval_seconds, server_restart_overlap_seconds=0, euid=nil, egid=nil, &block) # :yields: socket_server
      @logger = logger
      @sockaddr_get = sockaddr_get
      @server_polling_interval_seconds = server_polling_interval_seconds
      @server_restart_overlap_seconds = server_restart_overlap_seconds
      @euid = euid
      @egid = egid
      @server_setup = block
      @sysop = SystemOperation.new(@logger)
      @stop_state = nil
      @in_server_polling_sleep = false
      @signal_operation_queue = []
      @process_wait_count_table = {}
    end

    def server_polling_sleep
      catch(:end_of_server_polling_sleep) {
        begin
          @in_server_polling_sleep = true
          sleep(@server_polling_interval_seconds)
        ensure
          @in_server_polling_sleep = false
        end
      }
    end
    private :server_polling_sleep

    def interrupt_server_polling_sleep
      if (@in_server_polling_sleep) then
        throw(:end_of_server_polling_sleep)
      end
    end
    private :interrupt_server_polling_sleep

    # should be called from signal(2) handler
    def signal_stop_graceful
      @stop_state ||= :graceful
      interrupt_server_polling_sleep
      nil
    end

    # should be called from signal(2) handler
    def signal_stop_forced
      @stop_state ||= :forced
      interrupt_server_polling_sleep
      nil
    end

    # should be called from signal(2) handler
    def signal_restart_graceful
      @signal_operation_queue << :restart_graceful
      interrupt_server_polling_sleep
      nil
    end

    # should be called from signal(2) handler
    def signal_restart_forced
      @signal_operation_queue << :restart_forced
      interrupt_server_polling_sleep
      nil
    end

    # should be called from signal(2) handler
    def signal_stat_get(reset: true)
      if (reset) then
        @signal_operation_queue << :stat_get_and_reset
      else
        @signal_operation_queue << :stat_get_no_reset
      end
      interrupt_server_polling_sleep
      nil
    end

    # should be called from signal(2) handler
    def signal_stat_stop
      @signal_operation_queue << :stat_stop
      interrupt_server_polling_sleep
      nil
    end

    # should be called from signal(2) handler
    def signal_server_down
      interrupt_server_polling_sleep
      nil
    end

    def server_stop_graceful(pid)
      @sysop.send_signal(pid, SIGNAL_STOP_GRACEFUL)
    end
    private :server_stop_graceful

    def server_stop_forced(pid)
      @sysop.send_signal(pid, SIGNAL_STOP_FORCED)
    end
    private :server_stop_forced

    def server_socket_option(server_socket, server_address)
      if (server_address.backlog) then
        if (@sysop.listen(server_socket, server_address.backlog)) then
          @logger.info("server socket backlog: #{server_address.backlog}")
        else
          @logger.warn('server socket backlog cannot be changed.')
        end
      else
        @logger.info('server socket backlog is not changed.')
      end

      if (server_address.type == :unix) then
        if (server_address.mode) then
          if (@sysop.chmod(server_address.mode, server_address.path)) then
            @logger.info("unix domain server socket mode: #{'%04o' % server_address.mode}")
          else
            @logger.warn('unix domain server socket mode cannot be changed.')
          end
        else
          @logger.info('unix domain server socket mode is not changed.')
        end

        if (server_address.owner || server_address.group) then
          if (@sysop.chown(server_address.owner, server_address.group, server_address.path)) then
            @logger.info("unix domain server socket ownership: <#{server_address.owner}> <#{server_address.group}>")
          else
            @logger.warn('unix domain server socket ownership cannot be changed.')
          end
        else
          @logger.info('unix domain server socket ownership is not changed.')
        end
      end

      nil
    end
    private :server_socket_option

    def server_socket_close(server_socket, server_address)
      # get local_address before close(2)
      server_socket_address = @sysop.get_sockaddr(server_socket) || server_address

      if (@sysop.close(server_socket)) then
        @logger.info("close server socket: #{server_socket_address}")
      else
        @logger.warn("failed to close server socket: #{server_socket_address}")
      end

      if (server_address.type == :unix) then
        if (@sysop.unlink(server_address.path)) then
          @logger.info("delete unix domain server socket: #{server_address}")
        else
          @logger.warn("failed to delete unix domain server socket: #{server_address}")
        end
      end

      nil
    end
    private :server_socket_close

    def add_terminated_child_process(pid)
      @process_wait_count_table[pid] = 0
      pid
    end
    private :add_terminated_child_process

    def wait_terminated_child_processes
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

      nil
    end
    private :wait_terminated_child_processes

    def run_server(server_socket)
      read_write = @sysop.pipe
      unless (read_write) then
        @logger.error('failed to start server.')
        return
      end
      latch_read_io, latch_write_io = read_write

      pid = @sysop.fork{
        begin
          latch_read_io.close

          if (@egid) then
            @logger.info("change group privilege from #{Process::GID.eid} to #{@egid}")
            Process::GID.change_privilege(@egid)
          end

          if (@euid) then
            @logger.info("change user privilege from #{Process::UID.eid} to #{@euid}")
            Process::UID.change_privilege(@euid)
          end

          server = SocketServer.new
          @server_setup.call(server)
          server.setup(server_socket) # ready to accept signal(2)
          Signal.trap(SIGNAL_STOP_GRACEFUL) { server.signal_stop_graceful }
          Signal.trap(SIGNAL_STOP_FORCED) { server.signal_stop_forced }
          Signal.trap(SIGNAL_STAT_GET_AND_RESET) { server.signal_stat_get(reset: true) }
          Signal.trap(SIGNAL_STAT_GET_NO_RESET) { server.signal_stat_get(reset: false) }
          Signal.trap(SIGNAL_STAT_STOP) { server.signal_stat_stop }
        rescue
          @logger.error("failed to setup server (pid: #{$$}) [#{$!} (#{$!.class})]")
          @logger.debug($!) if @logger.debug?
          raise
        end
        @logger.close

        latch_write_io.puts("server process (pid: #{$$}) is ready to go.")
        latch_write_io.close

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
        add_terminated_child_process(pid)
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
      @logger.info("open server socket: #{@sysop.get_sockaddr(server_socket) || server_address}")

      begin
        server_socket_option(server_socket, server_address)

        unless (server_pid = run_server(server_socket)) then
          @logger.fatal('failed to start daemon.')
          return 1
        end
        @logger.info("server process start (pid: #{server_pid})")

        @logger.info("start server polling (interval seconds: #{@server_polling_interval_seconds})")
        until (@stop_state)
          server_polling_sleep
          if (server_pid) then
            @logger.debug("server polling... (pid: #{server_pid})") if @logger.debug?
          else
            @logger.debug('server polling...') if @logger.debug?
          end

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

          while (! @stop_state && server_pid && sig_ope = @signal_operation_queue.shift)
            case (sig_ope)
            when :restart_graceful, :restart_forced
              if (next_server_address = @sysop.get_server_address(@sockaddr_get)) then
                if (next_server_address.to_address == server_address.to_address) then
                  if (next_server_address.to_option != server_address.to_option) then
                    server_address = next_server_address
                  end
                else
                  if (next_server_socket = @sysop.get_server_socket(next_server_address)) then
                    @logger.info("open server socket: #{@sysop.get_sockaddr(next_server_socket) || next_server_address}")
                    server_socket_close(server_socket, server_address)
                    server_socket = next_server_socket
                    server_address = next_server_address
                  else
                    @logger.warn("server socket continue: #{@sysop.get_sockaddr(server_socket) || server_address}")
                  end
                end
              else
                @logger.warn("server socket continue: #{@sysop.get_sockaddr(server_socket) || server_address}")
              end
              server_socket_option(server_socket, server_address)

              case (sig_ope)
              when :restart_graceful
                @logger.info("server graceful restart (pid: #{server_pid})")
              when :restart_forced
                @logger.info("server forced restart (pid: #{server_pid})")
              else
                @logger.warn("internal warning: unknown signal operation <#{sig_ope.inspect}>")
              end

              if (next_pid = run_server(server_socket)) then
                @logger.info("server process start (pid: #{next_pid})")

                if (@server_restart_overlap_seconds > 0) then
                  @logger.info("server restart overlap (interval seconds: #{@server_restart_overlap_seconds})")
                  sleep(@server_restart_overlap_seconds)
                end

                case (sig_ope)
                when :restart_graceful
                  @logger.info("server graceful stop (pid: #{server_pid})")
                  server_stop_graceful(server_pid)
                when :restart_forced
                  @logger.info("server forced stop (pid: #{server_pid})")
                  server_stop_forced(server_pid)
                else
                  @logger.warn("internal warning: unknown signal operation <#{sig_ope.inspect}>")
                end

                add_terminated_child_process(server_pid)
                server_pid = next_pid
              else
                @logger.warn("server continue (pid: #{server_pid})")
              end
            when :stat_get_and_reset
              if (@sysop.send_signal(server_pid, SIGNAL_STAT_GET_AND_RESET)) then
                @logger.info("stat get(reset: true) (pid: #{server_pid})")
              else
                @logger.error("failed to stat get(reset: true) (pid: #{server_pid})")
              end
            when :stat_get_no_reset
              if (@sysop.send_signal(server_pid, SIGNAL_STAT_GET_NO_RESET)) then
                @logger.info("stat get(reset: false) (pid: #{server_pid})")
              else
                @logger.error("failed to stat get(reset: false) (pid: #{server_pid})")
              end
            when :stat_stop
              if (@sysop.send_signal(server_pid, SIGNAL_STAT_STOP)) then
                @logger.info("stat stop (pid: #{server_pid})")
              else
                @logger.error("failed to stat stop (pid: #{server_pid})")
              end
            else
              @logger.warn("internal warning: unknown signal operation <#{sig_ope.inspect}>")
            end
          end

          wait_terminated_child_processes
        end

        if (server_pid) then
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
            @logger.warn("internal warning: unknown stop state <#{@stop_state.inspect}>")
          end
        else
          @logger.warn('no server to stop.')
        end
      ensure
        server_socket_close(server_socket, server_address)
      end

      @logger.info('daemon stop.')
      return 0
    end
  end

  module Daemon
    class << self
      def get_id(name, id_mod)
        if (name) then
          case (name)
          when Integer
            name
          when /\A \d+ \z/x
            name.to_i
          else
            id_mod.from_name(name)
          end
        end
      end
      private :get_id

      def get_uid(user)
        get_id(user, Process::UID)
      end

      def get_gid(group)
        get_id(group, Process::GID)
      end
    end

    include ServerSignal

    DEFAULT = {
      daemonize: true,
      daemon_name: 'ruby'.freeze,
      daemon_debug: $DEBUG,
      daemon_nochdir: true,
      daemon_umask: 0037,
      status_file: nil,
      listen_address: nil,
      server_polling_interval_seconds: 3,
      server_restart_overlap_seconds: 0,
      server_privileged_user: nil,
      server_privileged_group: nil,

      signal_stop_graceful:      SIGNAL_STOP_GRACEFUL,
      signal_stop_forced:        SIGNAL_STOP_FORCED,
      signal_stat_get_and_reset: SIGNAL_STAT_GET_AND_RESET,
      signal_stat_get_no_reset:  SIGNAL_STAT_GET_NO_RESET,
      signal_stat_stop:          SIGNAL_STAT_STOP,
      signal_restart_graceful:   SIGNAL_RESTART_GRACEFUL,
      signal_restart_forced:     SIGNAL_RESTART_FORCED
    }.freeze

    # set the `status_file' parameter of the `start_daemon' method to
    # call this method.
    def self.running?(status_file_path)
      StatusFile.locked? status_file_path
    end

    # should be executed on the main thread sharing the stack with
    # signal(2) handlers
    def start_daemon(config, &block) # :yields: socket_server
      c = DEFAULT.dup
      c.update(config)

      File.umask(c[:daemon_umask])

      if (c[:status_file]) then
        status_file = StatusFile.new(c[:status_file])
        status_file.open
        status_file.lock or abort("#{c[:daemon_name]} daemon is already running.")
      end

      if (c[:daemonize]) then
        logger = Syslog::Logger.new(c[:daemon_name])
        def logger.close
          Syslog::Logger.syslog = nil
          Syslog.close
          nil
        end
      else
        logger = Logger.new(STDOUT)
        logger.progname = c[:daemon_name]
        def logger.close        # not close STDOUT
        end
      end

      if (c[:daemon_debug]) then
        logger.level = Logger::DEBUG
      else
        logger.level = Logger::INFO
      end

      if (c[:listen_address].respond_to? :call) then
        sockaddr_get = c[:listen_address]
      else
        sockaddr_get = proc{ c[:listen_address] }
      end

      euid = Daemon.get_uid(c[:server_privileged_user])
      egid = Daemon.get_gid(c[:server_privileged_group])

      root_process = RootProcess.new(logger, sockaddr_get, c[:server_polling_interval_seconds], c[:server_restart_overlap_seconds], euid, egid, &block)
      [ [ :signal_stop_graceful,      proc{ root_process.signal_stop_graceful }          ],
        [ :signal_stop_forced,        proc{ root_process.signal_stop_forced }            ],
        [ :signal_stat_get_and_reset, proc{ root_process.signal_stat_get(reset: true) }  ],
        [ :signal_stat_get_no_reset,  proc{ root_process.signal_stat_get(reset: false) } ],
        [ :signal_stat_stop,          proc{ root_process.signal_stat_stop }              ],
        [ :signal_restart_graceful,   proc{ root_process.signal_restart_graceful }       ],
        [ :signal_restart_forced,     proc{ root_process.signal_restart_forced }         ]
      ].each{|sig_key, sig_hook|
        if (signal = c[sig_key]) then
          Signal.trap(signal, &sig_hook)
        end
      }
      Signal.trap(:CHLD) { root_process.signal_server_down }

      if (c[:daemonize]) then
        Process.daemon(c[:daemon_nochdir])
      end

      # update after process ID changes in daemonization.
      if (c[:status_file]) then
        status_file.write({ 'pid' => $$ }.to_yaml)
      end

      status = root_process.start
      exit(status)
    end
    module_function :start_daemon
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
