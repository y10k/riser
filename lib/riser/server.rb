# -*- coding: utf-8 -*-

require 'io/wait'
require 'socket'
require 'thread'

module Riser
  class TimeoutSizedQueue
    # When the queue is processed at high speed without staying, it is
    # better to set the queue size to about 10 times the number of
    # waiting threads in order to increase the queue throughput. If
    # queue staying time is long, it is better to set a small queue
    # size so that you do not want to queue data at long time.
    def initialize(size, name: nil)
      @size = size
      @queue = []
      @closed = false
      @mutex = Mutex.new
      @push_cond = ConditionVariable.new
      @pop_cond = ConditionVariable.new
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
        unless (@queue.size < @size) then
          @stat_push_wait_count += 1 if @stat_enable
          @push_cond.wait(@mutex, timeout_seconds)
          unless (@queue.size < @size) then
            @stat_push_timeout_count += 1 if @stat_enable
            return
          end
        end
        @pop_cond.signal
        @queue.push(value)
        self
      }
    end

    def pop(timeout_seconds=0)
      if (timeout_seconds > 0) then
        @mutex.synchronize{
          if (@stat_enable) then
            @stat_pop_count += 1
            @stat_pop_average_queue_size = (@stat_pop_average_queue_size * (@stat_pop_count - 1) + @queue.size) / @stat_pop_count
          end
          if (@queue.empty?) then
            @closed and return
            @stat_pop_wait_count += 1 if @stat_enable
            @pop_cond.wait(@mutex, timeout_seconds)
            if (@queue.empty?) then
              @stat_pop_timeout_count += 1 if @stat_enable
              return
            end
          end
          @push_cond.signal
          @queue.shift
        }
      else
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
          @push_cond.signal
          @queue.shift
        }
      end
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
      @stat_pop_timeout_count       = 0
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

    # The bottle neck of queue is `ConditionVariable#wait'. In order to
    # improve queue performance, please adjust the queue size and number of
    # threads so that `push_wait_ratio' and `pop_wait_ratio' become smaller.
    def stat_get(reset: true)
      if (@stat_enable) then
        info = nil
        @mutex.synchronize{
          info = {
            queue_name:              @name,
            queue_size:              @size,
            closed:                  @closed,
            start_time:              @stat_start_time,
            push_average_queue_size: @stat_push_average_queue_size,
            push_count:              @stat_push_count,
            push_wait_count:         @stat_push_wait_count,
            push_timeout_count:      @stat_push_timeout_count,
            pop_average_queue_size:  @stat_pop_average_queue_size,
            pop_count:               @stat_pop_count,
            pop_wait_count:          @stat_pop_wait_count,
            pop_timeout_count:       @stat_pop_timeout_count
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
        info[:pop_timeout_ratio]  = info[:pop_timeout_count].to_f  / info[:pop_count]

        # sort
        [ :queue_name,
          :queue_size,
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
          :pop_wait_ratio,
          :pop_timeout_count,
          :pop_timeout_ratio
        ].each do |name|
          info[name] = info.delete(name)
        end

        info
      end
    end
  end

  class SocketThreadDispatcher
    def initialize(thread_queue_name)
      @thread_num = nil
      @thread_queue_name = thread_queue_name
      @thread_queue_size = nil
      @thread_queue_polling_timeout_seconds = nil
      @at_stop = nil
      @at_stat = nil
      @preprocess = nil
      @postprocess = nil
      @accept = nil
      @dispatch = nil
      @stop_state = nil
      @stat_operation_queue = []
    end

    attr_accessor :thread_num
    attr_accessor :thread_queue_size
    attr_accessor :thread_queue_polling_timeout_seconds

    def at_fork(&block)         # :yields:
    end

    def at_stop(&block)         # :yields:
      @at_stop = block
      nil
    end

    def at_stat(&block)         # :yields: stat_info
      @at_stat = block
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

    def dispatch(&block)        # :yields: socket
      @dispatch = block
      nil
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
      unless (@stat_operation_queue.empty?) then
        while (stat_ope = @stat_operation_queue.shift)
          case (stat_ope)
          when :get_and_reset
            queue.stat_start
            @at_stat.call(queue.stat_get(reset: true))
          when :get
            queue.stat_start
            @at_stat.call(queue.stat_get(reset: false))
          when :stop
            queue.stat_stop
          else
            raise "internal error: unknown stat operation: #{stat_ope}"
          end
        end
      end
    end
    private :apply_signal_stat

    # should be executed on the main thread sharing the stack with
    # signal(2) handlers
    def start
      @preprocess.call
      begin
        queue = TimeoutSizedQueue.new(@thread_queue_size, name: @thread_queue_name)
        begin
          thread_list = []
          @thread_num.times do
            thread_list << Thread.new{
              while (socket = queue.pop)
                begin
                  @dispatch.call(socket)
                ensure
                  socket.close unless socket.closed?
                end
              end
            }
          end

          catch (:end_of_server) {
            while (true)
              begin
                @stop_state and throw(:end_of_server)
                apply_signal_stat(queue)
                socket = @accept.call
              end until (socket)

              until (queue.push(socket, @thread_queue_polling_timeout_seconds))
                if (@stop_state == :forced) then
                  socket.close
                  throw(:end_of_server)
                end
                apply_signal_stat(queue)
              end
            end
          }
        ensure
          queue.close
        end

        @at_stop.call
        case (@stop_state)
        when :graceful
          for thread in thread_list
            thread.join
          end
        when :forced
          for thread in thread_list
            thread.kill
          end
        else
          raise "internal error: unknown @stop_state(#{@stop_state.inspect})"
        end
      ensure
        @postprocess.call
      end

      nil
    end
  end

  SocketProcess = Struct.new(:pid, :io, :command_queue)

  class SocketProcessDispatcher
    def initialize(process_queue_name, thread_queue_name)
      @accept_polling_timeout_seconds = nil
      @process_num = nil
      @process_queue_name = process_queue_name
      @process_queue_size = nil
      @process_queue_polling_timeout_seconds = nil
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
      @stop_state = nil
      @stat_operation_queue = []
    end

    attr_accessor :accept_polling_timeout_seconds
    attr_accessor :process_num
    attr_accessor :process_queue_size
    attr_accessor :process_queue_polling_timeout_seconds
    attr_accessor :thread_num
    attr_accessor :thread_queue_size
    attr_accessor :thread_queue_polling_timeout_seconds

    def at_fork(&block)         # :yields:
      @at_fork = block
      nil
    end

    def at_stop(&block)         # :yields:
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
      @stop_state ||= :graceful
      nil
    end

    # should be called from signal(2) handler
    def signal_stop_forced
      @stop_state ||= :forced
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

    def apply_signal_stat(process_queue, process_list)
      unless (@stat_operation_queue.empty?) then
        while (stat_ope = @stat_operation_queue.shift)
          case (stat_ope)
          when :get_and_reset
            process_queue.stat_start
            @at_stat.call(process_queue.stat_get(reset: true))
            for process in process_list
              unless (process.command_queue.closed?) then
                process.command_queue.push("STGR\n")
              end
            end
          when :get
            process_queue.stat_start
            @at_stat.call(process_queue.stat_get(reset: false))
            for process in process_list
              unless (process.command_queue.closed?) then
                process.command_queue.push("STGE\n")
              end
            end
          when :stop
            process_queue.stat_stop
            for process in process_list
              unless (process.command_queue.closed?) then
                process.command_queue.push("STST\n")
              end
            end
          else
            raise "internal error: unknown stat operation: #{stat_ope}"
          end
        end
      end
    end
    private :apply_signal_stat

    def start(server_socket)
      case (server_socket)
      when TCPServer, UNIXServer
        socket_class = server_socket.class.superclass
      else
        socket_class = IO
      end

      process_list = []
      @process_num.times do |pos|
        child_io, parent_io = UNIXSocket.socketpair
        pid = Process.fork{
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
          thread_dispatcher.preprocess(&@preprocess)
          thread_dispatcher.postprocess(&@postprocess)

          thread_dispatcher.accept{
            child_io.write("RADY\n")
            if (command = child_io.read(5)) then
              case (command)
              when "SEND\n"
                child_io.recv_io(socket_class)
              when "STGR\n"
                thread_dispatcher.signal_stat_get(reset: true); nil
              when "STGE\n"
                thread_dispatcher.signal_stat_get(reset: false); nil
              when "STST\n"
                thread_dispatcher.signal_stat_stop; nil
              when "STOG\n"
                thread_dispatcher.signal_stop_graceful; nil
              when "STOF\n"
                thread_dispatcher.signal_stop_forced; nil
              else
                raise "internal error: unknown command: #{command}"
              end
            end
          }
          thread_dispatcher.dispatch(&@dispatch)

          begin
            @at_fork.call
            thread_dispatcher.start
          ensure
            child_io.close
          end
        }
        child_io.close

        process_list << SocketProcess.new(pid, parent_io, Queue.new)
      end

      process_queue = TimeoutSizedQueue.new(@process_queue_size, name: @process_queue_name)
      thread_list = []
      process_list.each{|process|
        thread_list << Thread.new{
          until (process_queue.at_end_of_queue?)
            response = process.io.read(5) or break
            response == "RADY\n" or raise "internal error: unknown response: #{response}"
            unless (process.command_queue.empty?) then
              process.io.write(process.command_queue.pop)
            else
              until (process_queue.at_end_of_queue?)
                if (socket = process_queue.pop(@process_queue_polling_timeout_seconds)) then
                  process.io.write("SEND\n")
                  process.io.send_io(socket)
                  socket.close
                else
                  unless (process.command_queue.empty?) then
                    process.io.write(process.command_queue.pop)
                    break
                  end
                end
              end
            end
          end

          until (process.command_queue.empty?)
            response = process.io.read(5) or break
            response == "RADY\n" or raise "internal error: unknown response: #{response}"
            process.io.write(process.command_queue.pop)
          end
        }
      }

      catch (:end_of_server) {
        while (true)
          begin
            @stop_state and throw(:end_of_server)
            apply_signal_stat(process_queue, process_list)
            readable = server_socket.wait_readable(@accept_polling_timeout_seconds)
          end while (readable.nil?)

          socket = server_socket.accept
          until (process_queue.push(socket, @process_queue_polling_timeout_seconds))
            if (@stop_state == :forced) then
              socket.close
              throw(:end_of_server)
            end
            apply_signal_stat(process_queue, process_list)
          end
        end
      }

      case (@stop_state)
      when :graceful
        for process in process_list
          process.command_queue.push("STOG\n")
          process.command_queue.close
        end
        process_queue.close
        for thread in thread_list
          thread.join
        end
      when :forced
        for process in process_list
          process.command_queue.push("STOF\n")
          process.command_queue.close
        end
        process_queue.close
        for thread in thread_list
          thread.join
        end
      else
        raise "internal error: unknown @stop_state(#{@stop_state.inspect})"
      end

      for process in process_list
        Process.wait(process.pid)
        process.io.close
      end

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
      @thread_num = 4
      @thread_queue_size = 20
      @thread_queue_polling_timeout_seconds = 0.1
      @at_fork = NO_CALL
      @at_stop = NO_CALL
      @at_stat = NO_CALL
      @preprocess = NO_CALL
      @postprocess = NO_CALL
      @dispatch = nil
      @dispatcher = nil
    end

    attr_accessor :accept_polling_timeout_seconds
    attr_accessor :process_num
    attr_accessor :process_queue_size
    attr_accessor :process_queue_polling_timeout_seconds
    attr_accessor :thread_num
    attr_accessor :thread_queue_size
    attr_accessor :thread_queue_polling_timeout_seconds

    def at_fork(&block)         # :yields:
      @at_fork = block
      nil
    end

    def at_stop(&block)         # :yields:
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

    # should be executed on the main thread sharing the stack with
    # signal(2) handlers
    def start(server_socket)
      if (@process_num > 0) then
        @dispatcher = SocketProcessDispatcher.new('process_queue', 'thread_queue')
        @dispatcher.accept_polling_timeout_seconds = @accept_polling_timeout_seconds
        @dispatcher.process_num = @process_num
        @dispatcher.process_queue_size = @process_queue_size
        @dispatcher.process_queue_polling_timeout_seconds = @process_queue_polling_timeout_seconds
        @dispatcher.thread_num = @thread_num
        @dispatcher.thread_queue_size = @thread_queue_size
        @dispatcher.thread_queue_polling_timeout_seconds = @thread_queue_polling_timeout_seconds

        @dispatcher.at_fork(&@at_fork)
        @dispatcher.at_stop(&@at_stop)
        @dispatcher.at_stat(&@at_stat)
        @dispatcher.preprocess(&@preprocess)
        @dispatcher.postprocess(&@postprocess)
        @dispatcher.dispatch(&@dispatch)
        @dispatcher.start(server_socket)
      else
        @dispatcher = SocketThreadDispatcher.new('thread_queue')
        @dispatcher.thread_num = @thread_num
        @dispatcher.thread_queue_size = @thread_queue_size
        @dispatcher.thread_queue_polling_timeout_seconds = @thread_queue_polling_timeout_seconds

        @dispatcher.at_fork(&@at_fork)
        @dispatcher.at_stop(&@at_stop)
        @dispatcher.at_stat(&@at_stat)
        @dispatcher.preprocess(&@preprocess)
        @dispatcher.postprocess(&@postprocess)
        @dispatcher.accept{
          if (server_socket.wait_readable(@accept_polling_timeout_seconds) != nil) then
            server_socket.accept
          end
        }
        @dispatcher.dispatch(&@dispatch)
        @dispatcher.start
      end

      nil
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
