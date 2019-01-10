# -*- coding: utf-8 -*-

require 'fileutils'
require 'pp' if $DEBUG
require 'riser'
require 'riser/test'
require 'socket'
require 'test/unit'
require 'timeout'

module Riser::Test
  class TimeoutSizedQueueTest < Test::Unit::TestCase
    def setup
      @dt = 0.001
      @queue = Riser::TimeoutSizedQueue.new(3)
      @thread_num = 8
      @thread_list = []
      @count_max = 1000
    end

    def test_close
      assert_equal(false, @queue.closed?)
      @queue.close
      assert_equal(true, @queue.closed?)
      assert_nil(@queue.pop)
      assert_raise(RuntimeError) { @queue.push(:foo, @dt) }
    end

    def test_at_end_of_queue_with_data
      assert_equal(false, @queue.at_end_of_queue?)
      assert_not_nil(@queue.push(:foo, @dt))
      assert_equal(false, @queue.at_end_of_queue?)
      @queue.close
      assert_equal(false, @queue.at_end_of_queue?)
      @queue.pop
      assert_equal(true, @queue.at_end_of_queue?)
    end

    def test_at_end_of_queue_without_data
      assert_equal(false, @queue.at_end_of_queue?)
      @queue.close
      assert_equal(true, @queue.at_end_of_queue?)
    end

    def test_push_pop
      assert_equal(0, @queue.size)
      assert_equal(true, @queue.empty?)

      assert_not_nil(@queue.push(1, @dt))
      assert_equal(1, @queue.size)
      assert_equal(false, @queue.empty?)

      assert_not_nil(@queue.push(2, @dt))
      assert_equal(2, @queue.size)
      assert_equal(false, @queue.empty?)

      assert_not_nil(@queue.push(3, @dt))
      assert_equal(3, @queue.size)
      assert_equal(false, @queue.empty?)

      assert_nil(@queue.push(4, @dt))
      assert_equal(3, @queue.size)
      assert_equal(false, @queue.empty?)

      assert_equal(1, @queue.pop)
      assert_equal(2, @queue.size)
      assert_equal(false, @queue.empty?)

      assert_equal(2, @queue.pop)
      assert_equal(1, @queue.size)
      assert_equal(false, @queue.empty?)

      @queue.close
      assert_equal(1, @queue.size)
      assert_equal(false, @queue.empty?)

      assert_equal(3, @queue.pop)
      assert_equal(0, @queue.size)
      assert_equal(true, @queue.empty?)

      assert_nil(@queue.pop)
    end

    def test_push_pop_multithread
      @thread_num.times{
        t = { :pop_values => [] }
        t[:thread] = Thread.new{
          while (value = @queue.pop)
            t[:pop_values] << value
          end
        }
        @thread_list << t
      }

      push_values = (1..@count_max).to_a
      while (value = push_values.shift)
        begin
          is_success = @queue.push(value, @dt)
        end until (is_success)
      end
      @queue.close

      for t in @thread_list
        t[:thread].join
      end
      pp @thread_list if $DEBUG

      @thread_list.each_with_index do |t, i|
        assert(t[:pop_values].length > 0, "@thread_list[#{i}][:pop_values].length")
        (t[:pop_values].length - 1).times do |j|
          assert(t[:pop_values][j] < t[:pop_values][j + 1], "@thread_list[#{i}][#{:pop_values}][#{j}]")
        end
      end

      push_values = (1..@count_max).to_a
      pop_values = @thread_list.map{|t| t[:pop_values] }.flatten
      assert_equal(push_values, pop_values.sort)
    end
  end

  class MultiThreadSocketServerTest < Test::Unit::TestCase
    include Timeout

    def setup
      @unix_socket_path = Riser::TemporaryPath.make_unix_socket_path
      @server_timeout_seconds = 10
      @server_start_wait_path = 'socket_server_start'
      @server = Riser::SocketServer.new
      @store_path = 'socket_server_test'
      @recorder = CallRecorder.new(@store_path)
    end

    SIGNAL_STOP_GRACEFUL     = 'QUIT'
    SIGNAL_STOP_FORCED       = 'INT'
    SIGNAL_STAT_GET_RESET    = 'USR1'
    SIGNAL_STAT_GET_NO_RESET = 'WINCH'
    SIGNAL_STAT_STOP         = 'USR2'

    def start_server
      @pid = fork{
        Signal.trap(SIGNAL_STOP_GRACEFUL) { @server.signal_stop_graceful }
        Signal.trap(SIGNAL_STOP_FORCED) { @server.signal_stop_forced }
        Signal.trap(SIGNAL_STAT_GET_RESET) { @server.signal_stat_get }
        Signal.trap(SIGNAL_STAT_GET_NO_RESET) { @server.signal_stat_get(reset: false) }
        Signal.trap(SIGNAL_STAT_STOP) { @server.signal_stat_stop }
        FileUtils.touch(@server_start_wait_path)
        @server.start(UNIXServer.new(@unix_socket_path))
      }

      timeout(@server_timeout_seconds) {
        until (File.exist? @server_start_wait_path)
          # nothing to do.
        end
      }

      @pid
    end
    private :start_server

    def kill_and_wait(signal, pid)
      Process.kill(signal, pid)
      timeout(@server_timeout_seconds) {
        Process.wait(pid)
      }
    end

    def teardown
      if (@pid) then
        begin
          Process.kill(0, @pid)
        rescue Errno::ESRCH, Errno::EPERM
          # nothing to do
        else
          kill_and_wait('TERM', @pid)
        end
      end

      FileUtils.rm_f(@unix_socket_path)
      FileUtils.rm_f(@server_start_wait_path)
      FileUtils.rm_f(@store_path)
    end

    def connect_server
      timeout(@server_timeout_seconds) {
        begin
          UNIXSocket.new(@unix_socket_path)
        rescue Errno::ENOENT, Errno::ECONNREFUSED
          retry
        end
      }
    end
    private :connect_server

    def test_server_simple_request_response
      @server.dispatch{|socket|
        @recorder.call('dispatch')
        if (line = socket.gets)
          @recorder.call('request-response')
          socket.write(line)
        end
        socket.close
      }
      start_server

      s = connect_server
      begin
        s.write("HALO\n")
        assert_equal("HALO\n", s.gets)
        assert_nil(s.gets)
      ensure
        s.close
      end

      assert_equal(%w[ dispatch request-response ], @recorder.get_file_records)
    end

    def test_server_many_request_response
      @server.dispatch{|socket|
        @recorder.call('dispatch')
        if (line = socket.gets)
          @recorder.call('request-response')
          socket.write(line)
        end
        socket.close
      }
      start_server

      for word in %w[ foo bar baz ]
        s = connect_server
        begin
          s.write("#{word}\n")
          assert_equal("#{word}\n", s.gets, "word: #{word}")
          assert_nil(s.gets)
        ensure
          s.close
        end
      end

      assert_equal(%w[ dispatch request-response ] * 3, @recorder.get_file_records)
    end

    def test_server_hooks
      @server.at_fork{ @recorder.call('at_fork') } # should be ignored at multi-thread server
      @server.at_stop{ @recorder.call('at_stop') }
      @server.preprocess{ @recorder.call('preprocess') }
      @server.postprocess{ @recorder.call('postprocess') }
      @server.dispatch{|socket|
        @recorder.call('dispatch')
        if (line = socket.gets)
          @recorder.call('request-response')
          socket.write(line)
        end
        socket.close
      }
      server_pid = start_server

      s = connect_server
      begin
        s.write("HALO\n")
        assert_equal("HALO\n", s.gets)
        assert_nil(s.gets)
      ensure
        s.close
      end
      kill_and_wait(SIGNAL_STOP_GRACEFUL, server_pid)

      assert_equal(%w[
                     preprocess
                     dispatch
                     request-response
                     at_stop
                     postprocess
                   ], @recorder.get_file_records)
    end

    def test_server_stop_graceful
      server_polling_timeout_seconds = 0.001
      @server.accept_polling_timeout_seconds = server_polling_timeout_seconds
      @server.thread_queue_polling_timeout_seconds = server_polling_timeout_seconds

      @server.at_stop{ @recorder.call('at_stop') }
      @server.dispatch{|socket|
        @recorder.call('dispatch')
        while (line = socket.gets)
          @recorder.call('request-response')
          socket.write(line)
        end
        socket.close
      }
      server_pid = start_server

      s = connect_server
      begin
        s.write("foo\n")
        assert_equal("foo\n", s.gets)

        Process.kill(SIGNAL_STOP_GRACEFUL, server_pid)
        sleep(server_polling_timeout_seconds * 10)

        s.write("bar\n")
        assert_equal("bar\n", s.gets)
        s.write("baz\n")
        assert_equal("baz\n", s.gets)
      ensure
        s.close
      end
      Process.wait(server_pid)

      assert_equal(%w[
                     dispatch
                     request-response
                     at_stop
                     request-response
                     request-response
                   ], @recorder.get_file_records)
    end

    def test_server_stop_forced
      server_polling_timeout_seconds = 0.001
      @server.accept_polling_timeout_seconds = server_polling_timeout_seconds
      @server.thread_queue_polling_timeout_seconds = server_polling_timeout_seconds

      @server.at_stop{ @recorder.call('at_stop') }
      @server.dispatch{|socket|
        @recorder.call('dispatch')
        while (line = socket.gets)
          @recorder.call('request-response')
          socket.write(line)
        end
        socket.close
      }
      server_pid = start_server

      s = connect_server
      begin
        s.write("foo\n")
        assert_equal("foo\n", s.gets)

        Process.kill(SIGNAL_STOP_FORCED, server_pid)
        sleep(server_polling_timeout_seconds * 10)

        assert_nil(s.gets 'should be closed by by server')
      ensure
        s.close
      end
      Process.wait(server_pid)

      assert_equal(%w[
                     dispatch
                     request-response
                     at_stop
                   ], @recorder.get_file_records)
    end

    def test_server_stat_default
      server_polling_timeout_seconds = 0.001
      @server.accept_polling_timeout_seconds = server_polling_timeout_seconds
      @server.thread_queue_polling_timeout_seconds = server_polling_timeout_seconds

      @server.dispatch{|socket|
        @recorder.call('dispatch')
        if (line = socket.gets)
          @recorder.call('request-response')
          socket.write(line)
        end
        socket.close
      }
      server_pid = start_server
      sleep(server_polling_timeout_seconds * 10)

      Process.kill(SIGNAL_STAT_GET_RESET, server_pid)
      sleep(server_polling_timeout_seconds * 10)

      s = connect_server
      begin
        s.write("HALO\n")
        assert_equal("HALO\n", s.gets)
        assert_nil(s.gets)
      ensure
        s.close
      end

      Process.kill(SIGNAL_STAT_GET_NO_RESET, server_pid)
      sleep(server_polling_timeout_seconds * 10)

      Process.kill(SIGNAL_STAT_STOP, server_pid)
      sleep(server_polling_timeout_seconds * 10)

      assert_equal(%w[ dispatch request-response ], @recorder.get_file_records)
    end

    def test_server_stat_hook
      server_polling_timeout_seconds = 0.001
      @server.accept_polling_timeout_seconds = server_polling_timeout_seconds
      @server.thread_queue_polling_timeout_seconds = server_polling_timeout_seconds

      @server.at_stat{|info|
        @recorder.call('stat')
        pp info if $DEBUG
      }
      @server.dispatch{|socket|
        @recorder.call('dispatch')
        if (line = socket.gets)
          @recorder.call('request-response')
          socket.write(line)
        end
        socket.close
      }
      server_pid = start_server
      sleep(server_polling_timeout_seconds * 10)

      Process.kill(SIGNAL_STAT_GET_RESET, server_pid)
      sleep(server_polling_timeout_seconds * 10)

      s = connect_server
      begin
        s.write("foo\n")
        assert_equal("foo\n", s.gets)
        assert_nil(s.gets)
      ensure
        s.close
      end

      Process.kill(SIGNAL_STAT_GET_RESET, server_pid)
      sleep(server_polling_timeout_seconds * 10)

      s = connect_server
      begin
        s.write("bar\n")
        assert_equal("bar\n", s.gets)
        assert_nil(s.gets)
      ensure
        s.close
      end

      Process.kill(SIGNAL_STAT_GET_RESET, server_pid)
      sleep(server_polling_timeout_seconds * 10)

      assert_equal(%w[
                     stat
                     dispatch
                     request-response
                     stat
                     dispatch
                     request-response
                     stat
                   ], @recorder.get_file_records)
    end

    def test_server_stat_hook_no_reset
      server_polling_timeout_seconds = 0.001
      @server.accept_polling_timeout_seconds = server_polling_timeout_seconds
      @server.thread_queue_polling_timeout_seconds = server_polling_timeout_seconds

      @server.at_stat{|info|
        @recorder.call('stat')
        pp info if $DEBUG
      }
      @server.dispatch{|socket|
        @recorder.call('dispatch')
        if (line = socket.gets)
          @recorder.call('request-response')
          socket.write(line)
        end
        socket.close
      }
      server_pid = start_server
      sleep(server_polling_timeout_seconds * 10)

      Process.kill(SIGNAL_STAT_GET_NO_RESET, server_pid)
      sleep(server_polling_timeout_seconds * 10)

      s = connect_server
      begin
        s.write("foo\n")
        assert_equal("foo\n", s.gets)
        assert_nil(s.gets)
      ensure
        s.close
      end

      Process.kill(SIGNAL_STAT_GET_NO_RESET, server_pid)
      sleep(server_polling_timeout_seconds * 10)

      s = connect_server
      begin
        s.write("bar\n")
        assert_equal("bar\n", s.gets)
        assert_nil(s.gets)
      ensure
        s.close
      end

      Process.kill(SIGNAL_STAT_GET_NO_RESET, server_pid)
      sleep(server_polling_timeout_seconds * 10)

      assert_equal(%w[
                     stat
                     dispatch
                     request-response
                     stat
                     dispatch
                     request-response
                     stat
                   ], @recorder.get_file_records)
    end
  end

  class MultiProcessSocketServerTest < Test::Unit::TestCase
    include Timeout

    def setup
      @unix_socket_path = Riser::TemporaryPath.make_unix_socket_path
      @server_timeout_seconds = 10
      @server_start_wait_path = 'socket_server_start'
      @server = Riser::SocketServer.new
      @server.process_num = 1
      @store_path = 'socket_server_test'
      @recorder = CallRecorder.new(@store_path)
    end

    SIGNAL_STOP_GRACEFUL     = 'TERM'
    SIGNAL_STOP_FORCED       = 'QUIT'
    SIGNAL_STAT_GET_RESET    = 'USR1'
    SIGNAL_STAT_GET_NO_RESET = 'WINCH'
    SIGNAL_STAT_STOP         = 'USR2'

    def start_server
      @pid = fork{
        Signal.trap(SIGNAL_STOP_GRACEFUL) { @server.signal_stop_graceful }
        Signal.trap(SIGNAL_STOP_FORCED) { @server.signal_stop_forced }
        Signal.trap(SIGNAL_STAT_GET_RESET) { @server.signal_stat_get }
        Signal.trap(SIGNAL_STAT_GET_NO_RESET) { @server.signal_stat_get(reset: false) }
        Signal.trap(SIGNAL_STAT_STOP) { @server.signal_stat_stop }
        FileUtils.touch(@server_start_wait_path)
        @server.start(UNIXServer.new(@unix_socket_path))
      }

      timeout(@server_timeout_seconds) {
        until (File.exist? @server_start_wait_path)
          # nothing to do.
        end
      }

      @pid
    end
    private :start_server

    def kill_and_wait(signal, pid)
      Process.kill(signal, pid)
      timeout(@server_timeout_seconds) {
        Process.wait(pid)
      }
    end

    def teardown
      if (@pid) then
        begin
          Process.kill(0, @pid)
        rescue Errno::ESRCH, Errno::EPERM
          # nothing to do
        else
          kill_and_wait(SIGNAL_STOP_GRACEFUL, @pid)
        end
      end

      FileUtils.rm_f(@unix_socket_path)
      FileUtils.rm_f(@server_start_wait_path)
      FileUtils.rm_f(@store_path)
    end

    def connect_server
      timeout(@server_timeout_seconds) {
        begin
          UNIXSocket.new(@unix_socket_path)
        rescue Errno::ENOENT, Errno::ECONNREFUSED
          retry
        end
      }
    end
    private :connect_server

    def test_server_simple_request_response
      @server.dispatch{|socket|
        @recorder.call('dispatch')
        if (line = socket.gets)
          @recorder.call('request-response')
          socket.write(line)
        end
        socket.close
      }
      start_server

      s = connect_server
      begin
        s.write("HALO\n")
        assert_equal("HALO\n", s.gets)
        assert_nil(s.gets)
      ensure
        s.close
      end

      assert_equal(%w[ dispatch request-response ], @recorder.get_file_records)
    end

    def test_server_many_request_response
      @server.dispatch{|socket|
        @recorder.call('dispatch')
        if (line = socket.gets)
          @recorder.call('request-response')
          socket.write(line)
        end
        socket.close
      }
      start_server

      for word in %w[ foo bar baz ]
        s = connect_server
        begin
          s.write("#{word}\n")
          assert_equal("#{word}\n", s.gets, "word: #{word}")
          assert_nil(s.gets)
        ensure
          s.close
        end
      end

      assert_equal(%w[ dispatch request-response ] * 3, @recorder.get_file_records)
    end

    def test_server_hooks
      @server.at_fork{ @recorder.call('at_fork') }
      @server.at_stop{ @recorder.call('at_stop') }
      @server.preprocess{ @recorder.call('preprocess') }
      @server.postprocess{ @recorder.call('postprocess') }
      @server.dispatch{|socket|
        @recorder.call('dispatch')
        if (line = socket.gets)
          @recorder.call('request-response')
          socket.write(line)
        end
        socket.close
      }
      server_pid = start_server

      s = connect_server
      begin
        s.write("HALO\n")
        assert_equal("HALO\n", s.gets)
        assert_nil(s.gets)
      ensure
        s.close
      end
      kill_and_wait(SIGNAL_STOP_GRACEFUL, server_pid)

      assert_equal(%w[
                     at_fork
                     preprocess
                     dispatch
                     request-response
                     at_stop
                     postprocess
                   ], @recorder.get_file_records)
    end

    def test_server_stop_graceful
      server_polling_timeout_seconds = 0.001
      @server.accept_polling_timeout_seconds = server_polling_timeout_seconds
      @server.process_queue_polling_timeout_seconds = server_polling_timeout_seconds
      @server.thread_queue_polling_timeout_seconds = server_polling_timeout_seconds

      @server.at_stop{ @recorder.call('at_stop') }
      @server.dispatch{|socket|
        @recorder.call('dispatch')
        while (line = socket.gets)
          @recorder.call('request-response')
          socket.write(line)
        end
        socket.close
      }
      server_pid = start_server

      s = connect_server
      begin
        s.write("foo\n")
        assert_equal("foo\n", s.gets)

        Process.kill(SIGNAL_STOP_GRACEFUL, server_pid)
        sleep(server_polling_timeout_seconds * 10)

        s.write("bar\n")
        assert_equal("bar\n", s.gets)
        s.write("baz\n")
        assert_equal("baz\n", s.gets)
      ensure
        s.close
      end
      Process.wait(server_pid)

      assert_equal(%w[
                     dispatch
                     request-response
                     at_stop
                     request-response
                     request-response
                   ], @recorder.get_file_records)
    end

    def test_server_stop_forced
      server_polling_timeout_seconds = 0.001
      @server.accept_polling_timeout_seconds = server_polling_timeout_seconds
      @server.process_queue_polling_timeout_seconds = server_polling_timeout_seconds
      @server.thread_queue_polling_timeout_seconds = server_polling_timeout_seconds

      @server.at_stop{ @recorder.call('at_stop') }
      @server.dispatch{|socket|
        @recorder.call('dispatch')
        while (line = socket.gets)
          @recorder.call('request-response')
          socket.write(line)
        end
        socket.close
      }
      server_pid = start_server

      s = connect_server
      begin
        s.write("foo\n")
        assert_equal("foo\n", s.gets)

        Process.kill(SIGNAL_STOP_FORCED, server_pid)
        sleep(server_polling_timeout_seconds * 10)

        assert_nil(s.gets 'should be closed by by server')
      ensure
        s.close
      end
      Process.wait(server_pid)

      assert_equal(%w[
                     dispatch
                     request-response
                     at_stop
                   ], @recorder.get_file_records)
    end

    def test_server_stat_default
      server_polling_timeout_seconds = 0.001
      @server.accept_polling_timeout_seconds = server_polling_timeout_seconds
      @server.process_queue_polling_timeout_seconds = server_polling_timeout_seconds
      @server.thread_queue_polling_timeout_seconds = server_polling_timeout_seconds

      @server.dispatch{|socket|
        @recorder.call('dispatch')
        if (line = socket.gets)
          @recorder.call('request-response')
          socket.write(line)
        end
        socket.close
      }
      server_pid = start_server
      sleep(server_polling_timeout_seconds * 20)

      Process.kill(SIGNAL_STAT_GET_RESET, server_pid)
      sleep(server_polling_timeout_seconds * 20)

      s = connect_server
      begin
        s.write("HALO\n")
        assert_equal("HALO\n", s.gets)
        assert_nil(s.gets)
      ensure
        s.close
      end

      Process.kill(SIGNAL_STAT_GET_NO_RESET, server_pid)
      sleep(server_polling_timeout_seconds * 20)

      Process.kill(SIGNAL_STAT_STOP, server_pid)
      sleep(server_polling_timeout_seconds * 20)

      assert_equal(%w[ dispatch request-response ], @recorder.get_file_records)
    end

    def test_server_stat_hook
      server_polling_timeout_seconds = 0.001
      @server.accept_polling_timeout_seconds = server_polling_timeout_seconds
      @server.process_queue_polling_timeout_seconds = server_polling_timeout_seconds
      @server.thread_queue_polling_timeout_seconds = server_polling_timeout_seconds

      @server.at_stat{|info|
        @recorder.call('stat')
        pp info if $DEBUG
      }
      @server.dispatch{|socket|
        @recorder.call('dispatch')
        if (line = socket.gets)
          @recorder.call('request-response')
          socket.write(line)
        end
        socket.close
      }
      server_pid = start_server
      sleep(server_polling_timeout_seconds * 20)

      Process.kill(SIGNAL_STAT_GET_RESET, server_pid)
      sleep(server_polling_timeout_seconds * 20)

      s = connect_server
      begin
        s.write("foo\n")
        assert_equal("foo\n", s.gets)
        assert_nil(s.gets)
      ensure
        s.close
      end

      Process.kill(SIGNAL_STAT_GET_RESET, server_pid)
      sleep(server_polling_timeout_seconds * 20)

      s = connect_server
      begin
        s.write("bar\n")
        assert_equal("bar\n", s.gets)
        assert_nil(s.gets)
      ensure
        s.close
      end

      Process.kill(SIGNAL_STAT_GET_RESET, server_pid)
      sleep(server_polling_timeout_seconds * 20)

      assert_equal(%w[
                     stat
                     stat
                     dispatch
                     request-response
                     stat
                     stat
                     dispatch
                     request-response
                     stat
                     stat
                   ], @recorder.get_file_records)
    end

    def test_server_stat_hook_no_reset
      server_polling_timeout_seconds = 0.001
      @server.accept_polling_timeout_seconds = server_polling_timeout_seconds
      @server.process_queue_polling_timeout_seconds = server_polling_timeout_seconds
      @server.thread_queue_polling_timeout_seconds = server_polling_timeout_seconds

      @server.at_stat{|info|
        @recorder.call('stat')
        pp info if $DEBUG
      }
      @server.dispatch{|socket|
        @recorder.call('dispatch')
        if (line = socket.gets)
          @recorder.call('request-response')
          socket.write(line)
        end
        socket.close
      }
      server_pid = start_server
      sleep(server_polling_timeout_seconds * 20)

      Process.kill(SIGNAL_STAT_GET_NO_RESET, server_pid)
      sleep(server_polling_timeout_seconds * 20)

      s = connect_server
      begin
        s.write("foo\n")
        assert_equal("foo\n", s.gets)
        assert_nil(s.gets)
      ensure
        s.close
      end

      Process.kill(SIGNAL_STAT_GET_NO_RESET, server_pid)
      sleep(server_polling_timeout_seconds * 20)

      s = connect_server
      begin
        s.write("bar\n")
        assert_equal("bar\n", s.gets)
        assert_nil(s.gets)
      ensure
        s.close
      end

      Process.kill(SIGNAL_STAT_GET_NO_RESET, server_pid)
      sleep(server_polling_timeout_seconds * 20)

      assert_equal(%w[
                     stat
                     stat
                     dispatch
                     request-response
                     stat
                     stat
                     dispatch
                     request-response
                     stat
                     stat
                   ], @recorder.get_file_records)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
