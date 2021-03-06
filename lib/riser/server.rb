# -*- coding: utf-8 -*-

require 'io/wait'
require 'socket'
require 'tempfile'

module Riser
  class TimeoutSizedQueue
    def initialize(max_size, name: nil)
      @max_size = max_size
      @queue = []
      @closed = false
      @mutex = Thread::Mutex.new
      @push_cond = Thread::ConditionVariable.new
      @pop_cond = Thread::ConditionVariable.new
      @name = name && name.dup.freeze
      @stat_enable = false
    end

    def size
      @mutex.synchronize{ @queue.size }
    end

    alias length size

    def empty?
      @mutex.synchronize{ @queue.empty? }
    end

    def closed?
      @mutex.synchronize{ @closed }
    end

    def close
      @mutex.synchronize{
        @closed = true
        @pop_cond.broadcast
      }
      nil
    end

    def at_end_of_queue?
      @mutex.synchronize{ @closed && @queue.empty? }
    end

    def push(value, timeout_seconds)
      @mutex.synchronize{
        @closed and raise 'closed'
        if (@stat_enable) then
          @stat_push_count += 1
          @stat_push_average_queue_size = (@stat_push_average_queue_size * (@stat_push_count - 1) + @queue.size) / @stat_push_count
        end
        unless (@queue.size < @max_size) then
          @stat_push_wait_count += 1 if @stat_enable
          @push_cond.wait(@mutex, timeout_seconds)
          unless (@queue.size < @max_size) then
            @stat_push_timeout_count += 1 if @stat_enable
            return
          end
        end
        @pop_cond.signal if @queue.empty?
        @queue.push(value)
        self
      }
    end

    def pop
      @mutex.synchronize{
        if (@stat_enable) then
          @stat_pop_count += 1
          @stat_pop_average_queue_size = (@stat_pop_average_queue_size * (@stat_pop_count - 1) + @queue.size) / @stat_pop_count
        end
        while (@queue.empty?)
          @closed and return
          @stat_pop_wait_count += 1 if @stat_enable
          @pop_cond.wait(@mutex)
        end
        @push_cond.signal if (@queue.size == @max_size)
        @queue.shift
      }
    end

    def stat_reset_no_lock
      @stat_start_time              = Time.now
      @stat_push_average_queue_size = 0.0
      @stat_push_count              = 0
      @stat_push_wait_count         = 0
      @stat_push_timeout_count      = 0
      @stat_pop_average_queue_size  = 0.0
      @stat_pop_count               = 0
      @stat_pop_wait_count          = 0
    end
    private :stat_reset_no_lock

    def stat_start
      @mutex.synchronize{
        unless (@stat_enable) then
          stat_reset_no_lock
          @stat_enable = true
        end
      }
      nil
    end

    def stat_stop
      @mutex.synchronize{
        @stat_enable = false
      }
      nil
    end

    def stat_get(reset: true)
      if (@stat_enable) then
        info = nil
        @mutex.synchronize{
          info = {
            queue_name:              @name,
            max_size:                @max_size,
            closed:                  @closed,
            start_time:              @stat_start_time,
            push_average_queue_size: @stat_push_average_queue_size,
            push_count:              @stat_push_count,
            push_wait_count:         @stat_push_wait_count,
            push_timeout_count:      @stat_push_timeout_count,
            pop_average_queue_size:  @stat_pop_average_queue_size,
            pop_count:               @stat_pop_count,
            pop_wait_count:          @stat_pop_wait_count
          }

          if (reset) then
            stat_reset_no_lock
          end
        }

        info[:get_time]           = Time.now
        info[:elapsed_seconds]    = info[:get_time] - info[:start_time]
        info[:push_wait_ratio]    = info[:push_wait_count].to_f    / info[:push_count]
        info[:push_timeout_ratio] = info[:push_timeout_count].to_f / info[:push_count]
        info[:pop_wait_ratio]     = info[:pop_wait_count].to_f     / info[:pop_count]

        # sort
        [ :queue_name,
          :max_size,
          :closed,
          :start_time,
          :get_time,
          :elapsed_seconds,
          :push_average_queue_size,
          :push_count,
          :push_wait_count,
          :push_wait_ratio,
          :push_timeout_count,
          :push_timeout_ratio,
          :pop_average_queue_size,
          :pop_count,
          :pop_wait_count,
          :pop_wait_ratio
        ].each do |name|
          info[name] = info.delete(name)
        end

        info
      end
    end
  end

  module ServerSignal
    SIGNAL_STOP_GRACEFUL      = :TERM
    SIGNAL_STOP_FORCED        = :INT
    SIGNAL_STAT_GET_AND_RESET = :USR1
    SIGNAL_STAT_GET_NO_RESET  = :USR2
    SIGNAL_STAT_STOP          = :WINCH
    SIGNAL_RESTART_GRACEFUL   = :HUP
    SIGNAL_RESTART_FORCED     = :QUIT
  end

  module AcceptTimeout
    module ServerSocketMethod
    end
    ::TCPServer.class_eval{ include ServerSocketMethod }
    ::UNIXServer.class_eval{ include ServerSocketMethod }

    refine ServerSocketMethod do
      def accept_timeout(timeout_seconds)
        begin
          socket = accept_nonblock(exception: false)
          if (socket != :wait_readable) then
            socket
          else
            if (wait_readable(timeout_seconds) != nil) then
              socket = accept_nonblock(exception: false)
              # to ignore conflicting accept(2) at server restart overlap
              if (socket != :wait_readable) then
                socket
              end
            end
          end
        rescue Errno::EINTR   # EINTR is not captured by `exception: false'
          nil
        end
      end
    end
  end
  using AcceptTimeout

  class SocketThreadDispatcher
    def initialize(thread_queue_name)
      @thread_num = nil
      @thread_queue_name = thread_queue_name
      @thread_queue_size = nil
      @thread_queue_polling_timeout_seconds = nil
      @at_stop = nil
      @at_stat = nil
      @at_stat_get = nil
      @at_stat_stop = nil
      @preprocess = nil
      @postprocess = nil
      @accept = nil
      @accept_return = nil
      @dispatch = nil
      @dispose = nil
      @stop_state = nil
      @stat_operation_queue = []
    end

    attr_accessor :thread_num
    attr_accessor :thread_queue_size
    attr_accessor :thread_queue_polling_timeout_seconds

    def at_stop(&block)         # :yields: stop_state
      @at_stop = block
      nil
    end

    def at_stat(&block)         # :yields: stat_info
      @at_stat = block
      nil
    end

    def at_stat_get(&block)     # :yields: reset
      @at_stat_get = block
      nil
    end

    def at_stat_stop(&block)    # :yields:
      @at_stat_stop = block
      nil
    end

    def preprocess(&block)      # :yields:
      @preprocess = block
      nil
    end

    def postprocess(&block)     # :yields:
      @postprocess = block
      nil
    end

    def accept(&block)          # :yields:
      @accept = block
      nil
    end

    def accept_return(&block)   # :yields:
      @accept_return = block
      nil
    end

    def dispatch(&block)        # :yields: socket
      @dispatch = block
      nil
    end

    def dispose(&block)         # :yields:
      @dispose = block
      nil
    end

    # should be called from signal(2) handler
    def signal_stop_graceful
      @stop_state ||= :graceful
      nil
    end

    # should be called from signal(2) handler
    def signal_stop_forced
      if (! @stop_state || @stop_state == :graceful) then
        @stop_state = :forced
      end
      nil
    end

    # should be called from signal(2) handler
    def signal_stat_get(reset: true)
      if (reset) then
        @stat_operation_queue << :get_and_reset
      else
        @stat_operation_queue << :get
      end

      nil
    end

    # should be called from signal(2) handler
    def signal_stat_stop
      @stat_operation_queue << :stop
      nil
    end

    def apply_signal_stat(queue)
      while (stat_ope = @stat_operation_queue.shift)
        case (stat_ope)
        when :get_and_reset
          queue.stat_start
          @at_stat.call(queue.stat_get(reset: true))
          @at_stat_get.call(true)
        when :get
          queue.stat_start
          @at_stat.call(queue.stat_get(reset: false))
          @at_stat_get.call(false)
        when :stop
          queue.stat_stop
          @at_stat_stop.call
        else
          raise "internal error: unknown stat operation <#{stat_ope.inspect}>"
        end
      end
    end
    private :apply_signal_stat

    # should be executed on the main thread sharing the stack with
    # signal(2) handlers
    #
    # _server_socket is a dummy argument to call like
    # SocketProcessDispatcher#start.
    def start(_server_socket=nil)
      error_lock = Mutex.new
      last_error = nil

      @preprocess.call
      begin
        queue = TimeoutSizedQueue.new(@thread_queue_size, name: @thread_queue_name)
        begin
          thread_list = []
          @thread_num.times do |i|
            thread_list << Thread.start(i) {|thread_number|
              begin
                Thread.current[:number] = thread_number
                begin
                  while (socket = queue.pop)
                    begin
                      @dispatch.call(socket)
                    ensure
                      socket.close unless socket.closed?
                    end
                  end
                ensure
                  @dispose.call
                end
              rescue
                error_lock.synchronize{
                  last_error = $!
                }
              end
            }
          end

          catch (:end_of_server) {
            while (true)
              begin
                error_lock.synchronize{ last_error } and @stop_state = :forced
                @stop_state and throw(:end_of_server)
                apply_signal_stat(queue)
                socket = @accept.call
              end until (socket)

              until (queue.push(socket, @thread_queue_polling_timeout_seconds))
                error_lock.synchronize{ last_error } and @stop_state = :forced
                if (@stop_state == :forced) then
                  socket.close
                  @accept_return.call
                  throw(:end_of_server)
                end
                apply_signal_stat(queue)
              end
              @accept_return.call
            end
          }
        ensure
          queue.close
        end

        begin
          done = catch(:retry_stopping) {
            @at_stop.call(@stop_state)
            case (@stop_state)
            when :graceful
              until (thread_list.empty?)
                until (thread_list[0].join(@thread_queue_polling_timeout_seconds))
                  if (@stop_state == :forced) then
                    throw(:retry_stopping)
                  end
                end
                thread_list.shift
              end
            when :forced
              until (thread_list.empty?)
                thread_list[0].kill
                thread_list.shift
              end
            else
              raise "internal error: unknown stop state <#{@stop_state.inspect}>"
            end

            true
          }
        end until (done)
      ensure
        @postprocess.call
      end

      error_lock.synchronize{
        if (last_error) then
          raise last_error
        end
      }

      nil
    end
  end

  SocketProcess = Struct.new(:pid, :io) # :nodoc:

  class SocketProcessDispatcher
    include ServerSignal

    NO_CALL = proc{}            # :nodoc:

    def initialize(process_queue_name, thread_queue_name)
      @accept_polling_timeout_seconds = nil
      @process_num = nil
      @process_queue_name = process_queue_name
      @process_queue_size = nil
      @process_queue_polling_timeout_seconds = nil
      @process_send_io_polling_timeout_seconds = nil
      @thread_num = nil
      @thread_queue_name = thread_queue_name
      @thread_queue_size = nil
      @thread_queue_polling_timeout_seconds = nil
      @at_fork= nil
      @at_stop = nil
      @at_stat = nil
      @preprocess = nil
      @postprocess = nil
      @dispatch = nil
      @process_dispatcher = nil
    end

    attr_accessor :accept_polling_timeout_seconds
    attr_accessor :process_num
    attr_accessor :process_queue_size
    attr_accessor :process_queue_polling_timeout_seconds
    attr_accessor :process_send_io_polling_timeout_seconds
    attr_accessor :thread_num
    attr_accessor :thread_queue_size
    attr_accessor :thread_queue_polling_timeout_seconds

    def at_fork(&block)         # :yields:
      @at_fork = block
      nil
    end

    def at_stop(&block)         # :yields: stop_state
      @at_stop = block
      nil
    end

    def at_stat(&block)         # :yields: stat_info
      @at_stat = block
      nil
    end

    def preprocess(&block)      # :yields:
      @preprocess = block
      nil
    end

    def postprocess(&block)     # :yields:
      @postprocess = block
      nil
    end

    def dispatch(&block)        # :yields: accept_object
      @dispatch = block
      nil
    end

    # should be called from signal(2) handler
    def signal_stop_graceful
      @process_dispatcher.signal_stop_graceful if @process_dispatcher
      nil
    end

    # should be called from signal(2) handler
    def signal_stop_forced
      @process_dispatcher.signal_stop_forced if @process_dispatcher
      nil
    end

    # should be called from signal(2) handler
    def signal_stat_get(reset: true)
      @process_dispatcher.signal_stat_get(reset: reset) if @process_dispatcher
      nil
    end

    # should be called from signal(2) handler
    def signal_stat_stop
      @process_dispatcher.signal_stat_stop if @process_dispatcher
      nil
    end

    # after this method call is completed, the object will be ready to
    # accept `signal_...' methods.
    def setup
      @process_dispatcher = SocketThreadDispatcher.new(@process_queue_name)
      nil
    end

    SEND_CMD = "SEND\n".freeze   # :nodoc:
    SEND_LEN = SEND_CMD.bytesize # :nodoc:
    RADY_CMD = "RADY\n".freeze   # :nodoc:
    RADY_LEN = RADY_CMD.bytesize # :nodoc:

    def start(server_socket)
      case (server_socket)
      when TCPServer, UNIXServer
        socket_class = server_socket.class.superclass
      else
        socket_class = IO
      end

      parent_latch_file = Tempfile.open('riser_latch_')
      child_latch_file = File.open(parent_latch_file.path, File::RDWR)
      child_latch_file.flock(File::LOCK_EX | File::LOCK_NB) or raise "internal error: failed to lock latch file: #{parent_latch_file.path}"
      parent_latch_file.unlink

      process_list = []
      @process_num.times do |pos|
        child_io, parent_io = UNIXSocket.socketpair
        pid = Process.fork{
          server_socket.close
          parent_latch_file.close
          parent_io.close
          pos.times do |i|
            process_list[i].io.close
          end

          thread_dispatcher = SocketThreadDispatcher.new("#{@thread_queue_name}-#{pos}")
          thread_dispatcher.thread_num = @thread_num
          thread_dispatcher.thread_queue_size = @thread_queue_size
          thread_dispatcher.thread_queue_polling_timeout_seconds = @thread_queue_polling_timeout_seconds

          thread_dispatcher.at_stop(&@at_stop)
          thread_dispatcher.at_stat(&@at_stat)
          thread_dispatcher.at_stat_get(&NO_CALL)
          thread_dispatcher.at_stat_stop(&NO_CALL)
          thread_dispatcher.preprocess(&@preprocess)
          thread_dispatcher.postprocess(&@postprocess)

          thread_dispatcher.accept{
            if (child_io.wait_readable(@process_send_io_polling_timeout_seconds) != nil) then
              command = child_io.read(SEND_LEN)
              command == SEND_CMD or raise "internal error: unknown command <#{command.inspect}>"
              child_io.recv_io(socket_class)
            end
          }
          thread_dispatcher.accept_return{ child_io.write(RADY_CMD) }
          thread_dispatcher.dispatch(&@dispatch)
          thread_dispatcher.dispose(&NO_CALL)

          Signal.trap(SIGNAL_STOP_GRACEFUL) { thread_dispatcher.signal_stop_graceful }
          Signal.trap(SIGNAL_STOP_FORCED) { thread_dispatcher.signal_stop_forced }
          Signal.trap(SIGNAL_STAT_GET_AND_RESET) { thread_dispatcher.signal_stat_get(reset: true) }
          Signal.trap(SIGNAL_STAT_GET_NO_RESET) { thread_dispatcher.signal_stat_get(reset: false) }
          Signal.trap(SIGNAL_STAT_STOP) { thread_dispatcher.signal_stat_stop }

          # release flock(2)
          child_latch_file.close

          begin
            @at_fork.call
            thread_dispatcher.start
          ensure
            child_io.close
          end
        }
        child_io.close

        process_list << SocketProcess.new(pid, parent_io)
      end

      child_latch_file.close
      parent_latch_file.flock(File::LOCK_EX) # wait to release flock(2) at child processes
      parent_latch_file.close

      setup unless @process_dispatcher
      @process_dispatcher.thread_num = @process_num
      @process_dispatcher.thread_queue_size = @process_queue_size
      @process_dispatcher.thread_queue_polling_timeout_seconds = @process_queue_polling_timeout_seconds

      @process_dispatcher.at_stop{|state|
        case (state)
        when :graceful
          for process in process_list
            Process.kill(SIGNAL_STOP_GRACEFUL, process.pid)
          end
        when :forced
          for process in process_list
            Process.kill(SIGNAL_STOP_FORCED, process.pid)
          end
        end
      }
      @process_dispatcher.at_stat(&@at_stat)
      @process_dispatcher.at_stat_get{|reset|
        if (reset) then
          for process in process_list
            Process.kill(SIGNAL_STAT_GET_AND_RESET, process.pid)
          end
        else
          for process in process_list
            Process.kill(SIGNAL_STAT_GET_NO_RESET, process.pid)
          end
        end
      }
      @process_dispatcher.at_stat_stop{
        for process in process_list
          Process.kill(SIGNAL_STAT_STOP, process.pid)
        end
      }
      @process_dispatcher.preprocess(&NO_CALL)
      @process_dispatcher.postprocess(&NO_CALL)

      @process_dispatcher.accept{
        server_socket.accept_timeout(@accept_polling_timeout_seconds)
      }
      @process_dispatcher.accept_return(&NO_CALL)
      @process_dispatcher.dispatch{|socket|
        process = process_list[Thread.current[:number]]
        process.io.write(SEND_CMD)
        process.io.send_io(socket)
        response = process.io.read(RADY_LEN)
        response == RADY_CMD or raise "internal error: unknown response <#{response.inspect}>"
      }
      @process_dispatcher.dispose{
        process = process_list[Thread.current[:number]]
        Process.wait(process.pid)
        process.io.close
      }
      @process_dispatcher.start

      nil
    end
  end

  class SocketServer
    NO_CALL = proc{}            # :nodoc:

    def initialize
      @accept_polling_timeout_seconds = 0.1
      @process_num = 0
      @process_queue_size = 20
      @process_queue_polling_timeout_seconds = 0.1
      @process_send_io_polling_timeout_seconds = 0.1
      @thread_num = 4
      @thread_queue_size = 20
      @thread_queue_polling_timeout_seconds = 0.1
      @before_start = NO_CALL
      @at_fork = NO_CALL
      @at_stop = NO_CALL
      @at_stat = NO_CALL
      @preprocess = NO_CALL
      @postprocess = NO_CALL
      @after_stop = NO_CALL
      @dispatch = nil
      @dispatcher = nil
    end

    attr_accessor :accept_polling_timeout_seconds
    attr_accessor :process_num
    attr_accessor :process_queue_size
    attr_accessor :process_queue_polling_timeout_seconds
    attr_accessor :process_send_io_polling_timeout_seconds
    attr_accessor :thread_num
    attr_accessor :thread_queue_size
    attr_accessor :thread_queue_polling_timeout_seconds

    def before_start(&block)    # :yields: server_socket
      @before_start = block
      nil
    end

    def at_fork(&block)         # :yields:
      @at_fork = block
      nil
    end

    def at_stop(&block)         # :yields: stop_state
      @at_stop = block
      nil
    end

    def at_stat(&block)         # :yields: stat_info
      @at_stat = block
      nil
    end

    def preprocess(&block)      # :yields:
      @preprocess = block
      nil
    end

    def postprocess(&block)     # :yields:
      @postprocess = block
      nil
    end

    def after_stop(&block)      # :yields:
      @after_stop = block
      nil
    end

    def dispatch(&block)        # :yields: socket
      @dispatch = block
      nil
    end

    # should be called from signal(2) handler
    def signal_stop_graceful
      @dispatcher.signal_stop_graceful if @dispatcher
      nil
    end

    # should be called from signal(2) handler
    def signal_stop_forced
      @dispatcher.signal_stop_forced if @dispatcher
      nil
    end

    # should be called from signal(2) handler
    def signal_stat_get(reset: true)
      @dispatcher.signal_stat_get(reset: reset) if @dispatcher
      nil
    end

    # should be called from signal(2) handler
    def signal_stat_stop
      @dispatcher.signal_stat_stop if @dispatcher
      nil
    end

    # after this method call is completed, the object will be ready to
    # accept `signal_...' methods.
    def setup(server_socket)
      if (@process_num > 0) then
        @dispatcher = SocketProcessDispatcher.new('process_queue', 'thread_queue')
        @dispatcher.accept_polling_timeout_seconds = @accept_polling_timeout_seconds
        @dispatcher.process_num = @process_num
        @dispatcher.process_queue_size = @process_queue_size
        @dispatcher.process_queue_polling_timeout_seconds = @process_queue_polling_timeout_seconds
        @dispatcher.process_send_io_polling_timeout_seconds = @process_send_io_polling_timeout_seconds
        @dispatcher.thread_num = @thread_num
        @dispatcher.thread_queue_size = @thread_queue_size
        @dispatcher.thread_queue_polling_timeout_seconds = @thread_queue_polling_timeout_seconds

        @dispatcher.at_fork(&@at_fork)
        @dispatcher.at_stop(&@at_stop)
        @dispatcher.at_stat(&@at_stat)
        @dispatcher.preprocess(&@preprocess)
        @dispatcher.postprocess(&@postprocess)
        @dispatcher.dispatch(&@dispatch)
        @dispatcher.setup
      else
        @dispatcher = SocketThreadDispatcher.new('thread_queue')
        @dispatcher.thread_num = @thread_num
        @dispatcher.thread_queue_size = @thread_queue_size
        @dispatcher.thread_queue_polling_timeout_seconds = @thread_queue_polling_timeout_seconds

        @dispatcher.at_stop(&@at_stop)
        @dispatcher.at_stat(&@at_stat)
        @dispatcher.at_stat_get(&NO_CALL)
        @dispatcher.at_stat_stop(&NO_CALL)
        @dispatcher.preprocess(&@preprocess)
        @dispatcher.postprocess(&@postprocess)
        @dispatcher.accept{
          server_socket.accept_timeout(@accept_polling_timeout_seconds)
        }
        @dispatcher.accept_return(&NO_CALL)
        @dispatcher.dispatch(&@dispatch)
        @dispatcher.dispose(&NO_CALL)
      end

      nil
    end

    # should be executed on the main thread sharing the stack with
    # signal(2) handlers
    def start(server_socket)
      unless (@dispatcher) then
        setup(server_socket)
      end

      @before_start.call(server_socket)
      begin
        @dispatcher.start(server_socket)
      ensure
        @after_stop.call
      end

      nil
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
