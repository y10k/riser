# -*- coding: utf-8 -*-

require 'etc'
require 'fileutils'
require 'logger'
require 'riser'
require 'riser/test'
require 'socket'
require 'test/unit'
require 'timeout'

module Riser::Test
  class StatusFileTest < Test::Unit::TestCase
    def setup
      @filename = 'status_file_test'
      @st = Riser::StatusFile.new(@filename)
      @st.open
    end

    def teardown
      @st.close
      FileUtils.rm_f(@filename)
    end

    def test_lock
      assert(@st.lock)
    end

    def test_lock_exclusive
      lock_start = 'lock_start'
      lock_end = 'lock_end'
      begin
        pid = fork{
          st = Riser::StatusFile.new(@filename)
          st.open
          st.lock
          FileUtils.touch(lock_start)
          until (File.exist? lock_end)
            # nothing to do.
          end
        }

        begin
          until (File.exist? lock_start)
            # nothing to do.
          end
          assert(! @st.lock)
        ensure
          FileUtils.touch(lock_end)
          Process.wait(pid)
        end

        assert(@st.lock)
      ensure
        FileUtils.rm_f(lock_start)
        FileUtils.rm_f(lock_end)
      end
    end

    def test_write
      assert_equal('', IO.read(@filename))

      @st.write("123\n")
      assert_equal("123\n", IO.read(@filename))

      @st.write("1\n")
      assert_equal("1\n", IO.read(@filename))
    end
  end

  class RootProcessTest < Test::Unit::TestCase
    include Riser::ServerSignal
    include Timeout

    def setup
      @unix_socket_path = Riser::TemporaryPath.make_unix_socket_path
      @addr_conf = { type: :unix, path: @unix_socket_path }
      @daemon_timeout_seconds = 10
      @logger = Logger.new(STDOUT)
      def @logger.close         # not close STDOUT
      end
      @logger.level = ($DEBUG) ? Logger::DEBUG : Logger::FATAL.succ
      @dt = 0.001
      @daemon_start_wait_path = 'root_process_start'
      @recorder = CallRecorder.new('daemon_test')
    end

    def start_daemon(*args, &block)
      @pid = Process.fork{
        root_process = Riser::RootProcess.new(*args) {|server|
          server.accept_polling_timeout_seconds = @dt
          server.thread_queue_polling_timeout_seconds = @dt
          block.call(server)
        }
        Signal.trap(SIGNAL_STOP_GRACEFUL) { root_process.signal_stop_graceful }
        Signal.trap(SIGNAL_STOP_FORCED) { root_process.signal_stop_forced }
        Signal.trap(SIGNAL_STAT_GET_AND_RESET) { root_process.signal_stat_get(reset: true) }
        Signal.trap(SIGNAL_STAT_GET_NO_RESET) { root_process.signal_stat_get(reset: false) }
        Signal.trap(SIGNAL_STAT_STOP) { root_process.signal_stat_stop }
        Signal.trap(SIGNAL_RESTART_GRACEFUL) { root_process.signal_restart_graceful }
        Signal.trap(SIGNAL_RESTART_FORCED) { root_process.signal_restart_forced }
        FileUtils.touch(@daemon_start_wait_path)
        root_process.start
      }

      timeout(@daemon_timeout_seconds) {
        until (File.exist? @daemon_start_wait_path)
          # nothing to do.
        end
      }

      @pid
    end
    private :start_daemon

    def kill_and_wait(signal, pid)
      Process.kill(signal, pid)
      timeout(@daemon_timeout_seconds) {
        Process.wait(pid)
      }
    end
    private :kill_and_wait

    def teardown
      if (@pid) then
        begin
          Process.kill(0, @pid)
        rescue Errno::ESRCH, Errno::EPERM
          # nothing to do.
        else
          kill_and_wait(SIGNAL_STOP_GRACEFUL, @pid)
        end
      end

      FileUtils.rm_f(@unix_socket_path)
      FileUtils.rm_f(@daemon_start_wait_path)
      @recorder.dispose
    end

    def connect_server
      s = timeout(@daemon_timeout_seconds) {
        begin
          UNIXSocket.new(@unix_socket_path)
        rescue Errno::ENOENT, Errno::ECONNREFUSED
          sleep(@dt)
          retry
        end
      }

      if (block_given?) then
        begin
          yield(s)
        ensure
          s.close
        end
      else
        s
      end
    end
    private :connect_server

    def test_daemon_simple_request_response
      start_daemon(@logger, proc{ @addr_conf }, @dt) {|server|
        server.dispatch{|socket|
          @recorder.call('dispatch')
          if (line = socket.gets) then
            @recorder.call('request-response')
            socket.write(line)
          end
          socket.close
        }
      }

      connect_server{|s|
        s.write("HALO\n")
        assert_equal("HALO\n", s.gets)
        assert_nil(s.gets)
      }

      assert_equal(%w[ dispatch request-response ], @recorder.get_file_records)
    end

    def test_daemon_start_fail_bad_server_address
      pid = start_daemon(@logger, proc{ nil }, @dt) {}
      timeout(@daemon_timeout_seconds) {
        Process.wait(pid)
      }
    end

    def test_daemon_start_fail_not_open_server_socket
      s = UNIXServer.new(@unix_socket_path)
      begin
        pid = start_daemon(@logger, proc{ @addr_conf }, @dt) {}
        timeout(@daemon_timeout_seconds) {
          Process.wait(pid)
        }
      ensure
        s.close
      end
    end

    def test_daemon_start_change_backlog
      # in WSL, listen(2) of unix domain socket fails, so use tcp socket.
      start_daemon(@logger, proc{ { type: :tcp, host: 'localhost', port: 0, backlog: 10 } }, @dt) {}
    end

    def test_daemon_start_change_unix_domain_socket_permission
      start_daemon(@logger, proc{ { type: :unix, path: @unix_socket_path, mode: 0600, owner: Process.uid, group: Process.uid } }, @dt) {}
    end

    def test_daemon_start_fail_not_run_server
      pid = start_daemon(@logger, proc{ @addr_conf }, @dt) {
        Process.exit!(1)
      }
      timeout(@daemon_timeout_seconds) {
        Process.wait(pid)
      }
    end

    def test_daemon_server_hooks
      pid = start_daemon(@logger, proc{ @addr_conf }, @dt) {|server|
        server.process_num = 1
        server.before_start{|server_socket| @recorder.call('before_start') }
        server.at_fork{ @recorder.call('at_fork') }
        server.at_stop{|state| @recorder.call('at_stop') }
        server.preprocess{ @recorder.call('preprocess') }
        server.postprocess{ @recorder.call('postprocess') }
        server.after_stop{ @recorder.call('after_stop') }
        server.dispatch{|socket|
          @recorder.call('dispatch')
          if (line = socket.gets) then
            @recorder.call('request-response')
            socket.write(line)
          end
          socket.close
        }
      }

      connect_server{|s|
        s.write("HALO\n")
        assert_equal("HALO\n", s.gets)
        assert_nil(s.gets)
      }
      kill_and_wait(SIGNAL_STOP_GRACEFUL, pid)

      assert_equal(%w[
                     before_start
                     at_fork
                     preprocess
                     dispatch
                     request-response
                     at_stop
                     postprocess
                     after_stop
                   ], @recorder.get_file_records)
    end

    def test_daemon_server_down_and_restart
      start_daemon(@logger, proc{ @addr_conf }, @dt) {|server|
        server.before_start{|server_socket| @recorder.call(Process.pid.to_s) }
        server.dispatch{|socket|
          if (line = socket.gets) then
            socket.write(line)
          end
          socket.close
        }
      }

      connect_server{|s|
        s.write("HALO\n")
        assert_equal("HALO\n", s.gets)
        assert_nil(s.gets)
      }

      assert_equal(1, @recorder.get_file_records.length)
      assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])

      Process.kill(SIGNAL_STOP_FORCED, @recorder.get_file_records[0].to_i)
      sleep(@dt * 10)

      connect_server{|s|
        s.write("HALO\n")
        assert_equal("HALO\n", s.gets)
        assert_nil(s.gets)
      }

      assert_equal(2, @recorder.get_file_records.length)
      assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])
      assert_match(/\A \d+ \z/x, @recorder.get_file_records[1])
      assert_not_equal(@recorder.get_file_records[0], @recorder.get_file_records[1])
    end

    def test_daemon_server_down_and_restart_fail
      server_fail = 'test_server_fail'
      begin
        pid = start_daemon(@logger, proc{ @addr_conf }, @dt) {|server|
          if (File.exist? server_fail) then
            Process.exit!(1)
          end

          server.before_start{|server_socket| @recorder.call(Process.pid.to_s) }
          server.dispatch{|socket|
            if (line = socket.gets) then
              socket.write(line)
            end
            socket.close
          }
        }

        connect_server{|s|
          s.write("HALO\n")
          assert_equal("HALO\n", s.gets)
          assert_nil(s.gets)
        }

        assert_equal(1, @recorder.get_file_records.length)
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])

        FileUtils.touch(server_fail)
        Process.kill(SIGNAL_STOP_FORCED, @recorder.get_file_records[0].to_i)
        sleep(@dt * 50)         # need for 10s of milliseconds to stop the process

        assert_equal(1, @recorder.get_file_records.length)
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])

        kill_and_wait(SIGNAL_STOP_GRACEFUL, pid)
      ensure
        FileUtils.rm_f(server_fail)
      end
    end

    def test_daemon_server_restart_graceful
      pid = start_daemon(@logger, proc{ @addr_conf }, @dt) {|server|
        server.before_start{|server_socket| @recorder.call(Process.pid.to_s) }
        server.dispatch{|socket|
          if (line = socket.gets) then
            socket.write(line)
          end
          socket.close
        }
      }

      connect_server{|s|
        s.write("HALO\n")
        assert_equal("HALO\n", s.gets)
        assert_nil(s.gets)
      }

      assert_equal(1, @recorder.get_file_records.length)
      assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])

      Process.kill(SIGNAL_RESTART_GRACEFUL, pid)
      sleep(@dt * 50)           # need for 10s of milliseconds to stop the process

      connect_server{|s|
        s.write("HALO\n")
        assert_equal("HALO\n", s.gets)
        assert_nil(s.gets)
      }

      assert_equal(2, @recorder.get_file_records.length)
      assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])
      assert_match(/\A \d+ \z/x, @recorder.get_file_records[1])
      assert_not_equal(@recorder.get_file_records[0], @recorder.get_file_records[1])
    end

    def test_daemon_server_restart_graceful_fail
      server_fail = 'test_server_fail'
      begin
        pid = start_daemon(@logger, proc{ @addr_conf }, @dt) {|server|
          if (File.exist? server_fail) then
            Process.exit!(1)
          end

          server.before_start{|server_socket| @recorder.call(Process.pid.to_s) }
          server.dispatch{|socket|
            if (line = socket.gets) then
              socket.write(line)
            end
            socket.close
          }
        }

        connect_server{|s|
          s.write("HALO\n")
          assert_equal("HALO\n", s.gets)
          assert_nil(s.gets)
        }

        assert_equal(1, @recorder.get_file_records.length)
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])

        FileUtils.touch(server_fail)
        Process.kill(SIGNAL_RESTART_GRACEFUL, pid)
        sleep(@dt * 50)           # need for 10s of milliseconds to stop the process

        connect_server{|s|
          s.write("HALO\n")
          assert_equal("HALO\n", s.gets)
          assert_nil(s.gets)
        }

        assert_equal(1, @recorder.get_file_records.length)
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])
      ensure
        FileUtils.rm_f(server_fail)
      end
    end

    def test_daemon_server_restart_forced
      pid = start_daemon(@logger, proc{ @addr_conf }, @dt) {|server|
        server.before_start{|server_socket| @recorder.call(Process.pid.to_s) }
        server.dispatch{|socket|
          if (line = socket.gets) then
            socket.write(line)
          end
          socket.close
        }
      }

      connect_server{|s|
        s.write("HALO\n")
        assert_equal("HALO\n", s.gets)
        assert_nil(s.gets)
      }

      assert_equal(1, @recorder.get_file_records.length)
      assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])

      Process.kill(SIGNAL_RESTART_FORCED, pid)
      sleep(@dt * 50)           # need for 10s of milliseconds to stop the process

      connect_server{|s|
        s.write("HALO\n")
        assert_equal("HALO\n", s.gets)
        assert_nil(s.gets)
      }

      assert_equal(2, @recorder.get_file_records.length)
      assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])
      assert_match(/\A \d+ \z/x, @recorder.get_file_records[1])
      assert_not_equal(@recorder.get_file_records[0], @recorder.get_file_records[1])
    end

    def test_daemon_server_restart_forced_fail
      server_fail = 'test_server_fail'
      begin
        pid = start_daemon(@logger, proc{ @addr_conf }, @dt) {|server|
          if (File.exist? server_fail) then
            Process.exit!(1)
          end

          server.before_start{|server_socket| @recorder.call(Process.pid.to_s) }
          server.dispatch{|socket|
            if (line = socket.gets) then
              socket.write(line)
            end
            socket.close
          }
        }

        connect_server{|s|
          s.write("HALO\n")
          assert_equal("HALO\n", s.gets)
          assert_nil(s.gets)
        }

        assert_equal(1, @recorder.get_file_records.length)
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])

        FileUtils.touch(server_fail)
        Process.kill(SIGNAL_RESTART_FORCED, pid)
        sleep(@dt * 50)           # need for 10s of milliseconds to stop the process

        connect_server{|s|
          s.write("HALO\n")
          assert_equal("HALO\n", s.gets)
          assert_nil(s.gets)
        }

        assert_equal(1, @recorder.get_file_records.length)
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])
      ensure
        FileUtils.rm_f(server_fail)
      end
    end

    def test_daemon_server_restart_socket_reopen
      unix_socket_path_list = [
        Riser::TemporaryPath.make_unix_socket_path,
        Riser::TemporaryPath.make_unix_socket_path
      ]
      @unix_socket_path = unix_socket_path_list[0]

      begin
        addr_conf_list = [
          { type: :unix, path: unix_socket_path_list[0] },
          { type: :unix, path: unix_socket_path_list[1] }
        ]

        pid = start_daemon(@logger, proc{ addr_conf_list.shift }, @dt) {|server|
          server.before_start{|server_socket| @recorder.call(Process.pid.to_s) }
          server.dispatch{|socket|
            if (line = socket.gets) then
              socket.write(line)
            end
            socket.close
          }
        }

        connect_server{|s|
          s.write("HALO\n")
          assert_equal("HALO\n", s.gets)
          assert_nil(s.gets)
        }

        assert_equal(1, @recorder.get_file_records.length)
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])

        Process.kill(SIGNAL_RESTART_GRACEFUL, pid)
        sleep(@dt * 50)         # need for 10s of milliseconds to stop the process
        @unix_socket_path = unix_socket_path_list[1]

        connect_server{|s|
          s.write("HALO\n")
          assert_equal("HALO\n", s.gets)
          assert_nil(s.gets)
        }

        assert_equal(2, @recorder.get_file_records.length)
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[1])
        assert_not_equal(@recorder.get_file_records[0], @recorder.get_file_records[1])
      ensure
        FileUtils.rm_f(unix_socket_path_list)
      end
    end

    def test_daemon_server_restart_socket_backlog
      addr_conf_list = [
        { type: :unix, path: @unix_socket_path },
        # in WSL, listen(2) of unix domain socket fails, so use tcp socket.
        { type: :tcp, host: 'localhost', port: 0, backlog: 10 }
      ]

      pid = start_daemon(@logger, proc{ addr_conf_list.shift }, @dt) {|server|
        server.before_start{|server_socket| @recorder.call(Process.pid.to_s) }
        server.dispatch{|socket|
          if (line = socket.gets) then
            socket.write(line)
          end
          socket.close
        }
      }

      connect_server{|s|
        s.write("HALO\n")
        assert_equal("HALO\n", s.gets)
        assert_nil(s.gets)
      }

      assert_equal(1, @recorder.get_file_records.length)
      assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])

      Process.kill(SIGNAL_RESTART_GRACEFUL, pid)
      sleep(@dt * 50)         # need for 10s of milliseconds to stop the process

      assert_equal(2, @recorder.get_file_records.length)
      assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])
      assert_match(/\A \d+ \z/x, @recorder.get_file_records[1])
      assert_not_equal(@recorder.get_file_records[0], @recorder.get_file_records[1])
    end

    def test_daemon_server_restart_socket_permission
      unix_socket_path_list = [
        Riser::TemporaryPath.make_unix_socket_path,
        Riser::TemporaryPath.make_unix_socket_path
      ]
      @unix_socket_path = unix_socket_path_list[0]

      begin
        addr_conf_list = [
          { type: :unix, path: unix_socket_path_list[0] },
          { type: :unix, path: unix_socket_path_list[1], mode: 0600, owner: Process.uid, group: Process.uid }
        ]

        pid = start_daemon(@logger, proc{ addr_conf_list.shift }, @dt) {|server|
          server.before_start{|server_socket| @recorder.call(Process.pid.to_s) }
          server.dispatch{|socket|
            if (line = socket.gets) then
              socket.write(line)
            end
            socket.close
          }
        }

        connect_server{|s|
          s.write("HALO\n")
          assert_equal("HALO\n", s.gets)
          assert_nil(s.gets)
        }

        assert_equal(1, @recorder.get_file_records.length)
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])

        Process.kill(SIGNAL_RESTART_GRACEFUL, pid)
        sleep(@dt * 50)         # need for 10s of milliseconds to stop the process
        @unix_socket_path = unix_socket_path_list[1]

        connect_server{|s|
          s.write("HALO\n")
          assert_equal("HALO\n", s.gets)
          assert_nil(s.gets)
        }

        assert_equal(2, @recorder.get_file_records.length)
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[1])
        assert_not_equal(@recorder.get_file_records[0], @recorder.get_file_records[1])
      ensure
        FileUtils.rm_f(unix_socket_path_list)
      end
    end

    def test_daemon_server_restart_socket_reopen_fail_bad_server_address
      addr_conf_list = [ @addr_conf ]
      pid = start_daemon(@logger, proc{ addr_conf_list.shift }, @dt) {|server|
        server.before_start{|server_socket| @recorder.call(Process.pid.to_s) }
        server.dispatch{|socket|
          if (line = socket.gets) then
            socket.write(line)
          end
          socket.close
        }
      }

      connect_server{|s|
        s.write("HALO\n")
        assert_equal("HALO\n", s.gets)
        assert_nil(s.gets)
      }

      assert_equal(1, @recorder.get_file_records.length)
      assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])

      Process.kill(SIGNAL_RESTART_GRACEFUL, pid)
      sleep(@dt * 50)           # need for 10s of milliseconds to stop the process

      connect_server{|s|
        s.write("HALO\n")
        assert_equal("HALO\n", s.gets)
        assert_nil(s.gets)
      }

      assert_equal(2, @recorder.get_file_records.length)
      assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])
      assert_match(/\A \d+ \z/x, @recorder.get_file_records[1])
      assert_not_equal(@recorder.get_file_records[0], @recorder.get_file_records[1])
    end

    def test_daemon_server_restart_socket_reopen_fail_not_open_server_socket
      unix_socket_path_list = [
        Riser::TemporaryPath.make_unix_socket_path,
        Riser::TemporaryPath.make_unix_socket_path
      ]
      @unix_socket_path = unix_socket_path_list[0]
      s = UNIXServer.new(unix_socket_path_list[1])

      begin
        addr_conf_list = [
          { type: :unix, path: unix_socket_path_list[0] },
          { type: :unix, path: unix_socket_path_list[1] },
        ]

        pid = start_daemon(@logger, proc{ addr_conf_list.shift }, @dt) {|server|
          server.before_start{|server_socket| @recorder.call(Process.pid.to_s) }
          server.dispatch{|socket|
            if (line = socket.gets) then
              socket.write(line)
            end
            socket.close
          }
        }

        connect_server{|s|
          s.write("HALO\n")
          assert_equal("HALO\n", s.gets)
          assert_nil(s.gets)
        }

        assert_equal(1, @recorder.get_file_records.length)
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])

        Process.kill(SIGNAL_RESTART_GRACEFUL, pid)
        sleep(@dt * 50)         # need for 10s of milliseconds to stop the process

        connect_server{|s|
          s.write("HALO\n")
          assert_equal("HALO\n", s.gets)
          assert_nil(s.gets)
        }

        assert_equal(2, @recorder.get_file_records.length)
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[1])
        assert_not_equal(@recorder.get_file_records[0], @recorder.get_file_records[1])
      ensure
        s.close
        FileUtils.rm_f(unix_socket_path_list)
      end
    end

    def test_daemon_server_stat
      pid = start_daemon(@logger, proc{ @addr_conf }, @dt) {|server|
        server.at_stat{|info| @recorder.call('stat') }
        server.dispatch{|socket|
          if (line = socket.gets) then
            socket.write(line)
          end
          socket.close
        }
      }

      connect_server{|s|
        s.write("HALO\n")
        assert_equal("HALO\n", s.gets)
        assert_nil(s.gets)
      }

      Process.kill(SIGNAL_STAT_GET_AND_RESET, pid)
      sleep(@dt * 10)

      assert_equal(%w[ stat ], @recorder.get_file_records)

      Process.kill(SIGNAL_STAT_GET_NO_RESET, pid)
      sleep(@dt * 10)

      assert_equal(%w[ stat stat ], @recorder.get_file_records)

      Process.kill(SIGNAL_STAT_STOP, pid)
      sleep(@dt * 10)

      assert_equal(%w[ stat stat ], @recorder.get_file_records)
    end

    def test_daemon_server_down_ignored_signals
      server_fail = 'test_server_fail'
      begin
        pid = start_daemon(@logger, proc{ @addr_conf }, @dt) {|server|
          if (File.exist? server_fail) then
            Process.exit!(1)
          end

          server.before_start{|server_socket| @recorder.call(Process.pid.to_s) }
          server.at_stat{|info| @recorder.call('stat') }
          server.dispatch{|socket|
            if (line = socket.gets) then
              socket.write(line)
            end
            socket.close
          }
        }

        connect_server{|s|
          s.write("HALO\n")
          assert_equal("HALO\n", s.gets)
          assert_nil(s.gets)
        }

        assert_equal(1, @recorder.get_file_records.length)
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])

        FileUtils.touch(server_fail)
        Process.kill(SIGNAL_STOP_FORCED, @recorder.get_file_records[0].to_i)
        sleep(@dt * 50)         # need for 10s of milliseconds to stop the process

        assert_equal(1, @recorder.get_file_records.length)
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])

        Process.kill(SIGNAL_RESTART_GRACEFUL, pid)
        sleep(@dt * 50)         # need for 10s of milliseconds to stop the process

        assert_equal(1, @recorder.get_file_records.length)
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])

        Process.kill(SIGNAL_RESTART_FORCED, pid)
        sleep(@dt * 50)           # need for 10s of milliseconds to stop the process

        assert_equal(1, @recorder.get_file_records.length)
        assert_match(/\A \d+ \z/x, @recorder.get_file_records[0])

        Process.kill(SIGNAL_STAT_GET_AND_RESET, pid)
        sleep(@dt * 10)

        assert_equal(0, @recorder.get_file_records.count('stat'))

        Process.kill(SIGNAL_STAT_GET_NO_RESET, pid)
        sleep(@dt * 10)

        assert_equal(0, @recorder.get_file_records.count('stat'))

        Process.kill(SIGNAL_STAT_STOP, pid)
        sleep(@dt * 10)

        assert_equal(0, @recorder.get_file_records.count('stat'))

        kill_and_wait(SIGNAL_STOP_GRACEFUL, pid)
      ensure
        FileUtils.rm_f(server_fail)
      end
    end
  end

  class RootProcessSystemOperationTest < Test::Unit::TestCase
    def setup
      @logger = Logger.new(STDOUT)
      def @logger.close         # not close STDOUT
      end
      @logger.level = ($DEBUG) ? Logger::DEBUG : Logger::FATAL.succ
      @sysop = Riser::RootProcess::SystemOperation.new(@logger)
    end

    def test_get_server_address
      assert_equal(Riser::SocketAddress.parse(type: :tcp, host: 'example', port: 80),
                   @sysop.get_server_address(proc{ 'example:80' }))
    end

    def test_get_server_address_fail_get_address
      assert_nil(@sysop.get_server_address(proc{ raise 'abort' }))
    end

    def test_get_server_address_fail_parse_address
      assert_nil(@sysop.get_server_address(proc{ nil }))
    end

    def test_get_server_socket
      unix_addr = Riser::SocketAddress.parse(type: :unix, path: Riser::TemporaryPath.make_unix_socket_path)
      begin
        s = @sysop.get_server_socket(unix_addr)
        begin
          assert_instance_of(UNIXServer, s)
        ensure
          s.close
        end
      ensure
        FileUtils.rm_f(unix_addr.path)
      end
    end

    def test_get_server_socket_fail_socket_open
      unix_addr = Riser::SocketAddress.parse(type: :unix, path: Riser::TemporaryPath.make_unix_socket_path)
      begin
        s = unix_addr.open_server
        begin
          assert_nil(@sysop.get_server_socket(unix_addr))
        ensure
          s.close
        end
      ensure
        FileUtils.rm_f(unix_addr.path)
      end
    end

    def test_listen
      s = TCPServer.new(0)
      begin
        assert_equal(0, @sysop.listen(s, 10))
      ensure
        s.close
      end
    end

    def test_listen_fail
      o = Object.new
      def o.listen(backlog)
        raise 'abort'
      end
      assert_nil(@sysop.listen(o, 10))
    end

    def test_chmod
      target = 'chmod_test.tmp'
      FileUtils.touch(target)
      begin
        assert_equal([ target ], @sysop.chmod(0600, target))
      ensure
        FileUtils.rm_f(target)
      end
    end

    def test_chmod_fail
      target = 'chmod_test.tmp'
      assert(! (File.exist? target))
      assert_nil(@sysop.chmod(0600, target))
    end

    def test_chown
      target = 'chown_test.tmp'
      FileUtils.touch(target)
      begin
        assert_equal([ target ], @sysop.chown(Process.uid, Process.gid, target))
        assert_equal([ target ], @sysop.chown(Process.uid, -1,          target))
        assert_equal([ target ], @sysop.chown(-1,          Process.gid, target))

        pw = Etc.getpwuid(Process.uid)
        gr = Etc.getgrgid(Process.gid)
        assert_equal([ target ], @sysop.chown(pw.name, gr.name, target))
        assert_equal([ target ], @sysop.chown(pw.name, nil,     target))
        assert_equal([ target ], @sysop.chown(nil,     gr.name, target))
      ensure
        FileUtils.rm_f(target)
      end
    end

    def test_chown_fail
      target = 'chown_test.tmp'
      assert(! (File.exist? target))
      assert_nil(@sysop.chown(Process.uid, Process.gid, target))
      assert_nil(@sysop.chown(Process.uid, -1,          target))
      assert_nil(@sysop.chown(-1,          Process.gid, target))

      pw = Etc.getpwuid(Process.uid)
      gr = Etc.getgrgid(Process.gid)
      assert_nil(@sysop.chown(pw.name, gr.name, target))
      assert_nil(@sysop.chown(pw.name, nil,     target))
      assert_nil(@sysop.chown(nil,     gr.name, target))
    end

    def test_send_signal
      assert_equal(1, @sysop.send_signal($$, 0))
    end

    def test_send_signal_fail
      m_process = Object.new
      def m_process.kill(signal, pid)
        raise 'abort'
      end

      @sysop = Riser::RootProcess::SystemOperation.new(@logger, module_Process: m_process)
      assert_nil(@sysop.send_signal($$, 0))
    end

    def test_wait
      pid = fork{}
      assert_equal(pid, @sysop.wait(pid))
    end

    def test_wait_fail
      m_process = Object.new
      def m_process.wait(pid, flags)
        raise 'abort'
      end

      @sysop = Riser::RootProcess::SystemOperation.new(@logger, module_Process: m_process)
      assert_nil(@sysop.wait(1))
    end

    def test_pipe
      read_io, write_io = @sysop.pipe
      begin
        write_io << "HALO\n"
        assert_equal("HALO\n", read_io.gets)
      ensure
        read_io.close
        write_io.close
      end
    end

    def test_pipe_fail
      c_io = Object.new
      def c_io.pipe
        raise 'abort'
      end

      @sysop = Riser::RootProcess::SystemOperation.new(@logger, class_IO: c_io)
      assert_nil(@sysop.pipe)
    end

    def test_fork
      pid = @sysop.fork{}
      Process.wait(pid)
    end

    def test_fork_fail
      m_process = Object.new
      def m_process.fork
        raise 'abort'
      end

      @sysop = Riser::RootProcess::SystemOperation.new(@logger, module_Process: m_process)
      assert_nil(@sysop.fork{})
    end

    def test_gets
      read_io, write_io = IO.pipe
      begin
        write_io << "HALO\n"
        assert_equal("HALO\n", @sysop.gets(read_io))
      ensure
        read_io.close
        write_io.close
      end
    end

    def test_gets_fail
      o = Object.new
      def o.gets
        raise 'abort'
      end

      assert_nil(@sysop.gets(o))
    end

    def test_close
      f = File.open('/dev/null')
      assert_equal(f, @sysop.close(f))
    end

    def test_close_fail
      o = Object.new
      def o.close
        raise 'abort'
      end

      assert_nil(@sysop.close(o))
    end
  end

  class DaemonTest < Test::Unit::TestCase
    def test_get_uid
      assert_nil(Riser::Daemon.get_uid(nil))
      assert_equal(1000, Riser::Daemon.get_uid(1000))
      assert_equal(1000, Riser::Daemon.get_uid('1000'))

      pw = Etc.getpwuid(Process.uid)
      assert_equal(pw.uid, Riser::Daemon.get_uid(pw.name))

      assert_raise(ArgumentError) { Riser::Daemon.get_uid('nothing_user') }
    end

    def test_get_gid
      assert_nil(Riser::Daemon.get_gid(nil))
      assert_equal(1000, Riser::Daemon.get_gid(1000))
      assert_equal(1000, Riser::Daemon.get_gid('1000'))

      gr = Etc.getgrgid(Process.gid)
      assert_equal(gr.gid, Riser::Daemon.get_gid(gr.name))

      assert_raise(ArgumentError) { Riser::Daemon.get_gid('nothing_group') }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
