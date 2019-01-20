# -*- coding: utf-8 -*-

require 'fileutils'
require 'logger'
require 'riser'
require 'riser/test'
require 'socket'
require 'test/unit'
require 'timeout'

module Riser::Test
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
      @store_path = 'daemon_test'
      @recorder = CallRecorder.new(@store_path)
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
        root_process.start
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
      FileUtils.rm_f(@store_path)
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

    def test_daemon_server_restart_socket_reopen
      unix_socket_path_list = [
        Riser::TemporaryPath.make_unix_socket_path,
        Riser::TemporaryPath.make_unix_socket_path
      ]
      @unix_socket_path = unix_socket_path_list[0]

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
        sleep(@dt * 10)
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
      assert_equal(Riser::TCPSocketAddress.new('example', 80), @sysop.get_server_address(proc{ 'example:80' }))
    end

    def test_get_server_address_fail_get_address
      assert_nil(@sysop.get_server_address(proc{ raise 'abort' }))
    end

    def test_get_server_address_fail_parse_address
      assert_nil(@sysop.get_server_address(proc{ nil }))
    end

    def test_get_server_socket
      unix_addr = Riser::UNIXSocketAddress.new(Riser::TemporaryPath.make_unix_socket_path)
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
      unix_addr = Riser::UNIXSocketAddress.new(Riser::TemporaryPath.make_unix_socket_path)
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
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
