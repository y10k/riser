# -*- coding: utf-8 -*-

require 'io/wait'
require 'socket'
require 'thread'
require 'uri'

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
        @push_cond.signal
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
          :pop_wait_ratio
        ].each do |name|
          info[name] = info.delete(name)
        end

        info
      end
    end
  end

  class SocketAddress
    def initialize(type)
      @type = type
    end

    attr_reader :type

    def to_a
      [ @type ]
    end

    def ==(other)
      if (other.is_a? SocketAddress) then
        self.to_a == other.to_a
      else
        false
      end
    end

    def eql?(other)
      self == other
    end

    def hash
      to_a.hash ^ self.class.hash
    end

    def self.parse(config)
      unsquare = proc{|s| s.sub(/\A \[/x, '').sub(/\] \z/x, '') }
      case (config)
      when String
        case (config)
        when /\A tcp:/x
          uri = URI(config)
          if (uri.host && uri.port) then
            return TCPSocketAddress.new(unsquare.call(uri.host), uri.port)
          end
        when /\A unix:/x
          uri = URI(config)
          if (uri.path && ! uri.path.empty?) then
            return UNIXSocketAddress.new(uri.path)
          end
        when %r"\A [A-Za-z]+:/"x
          # unknown URI scheme
        when /\A (\S+):(\d+) \z/x
          host = $1
          port = $2.to_i
          return TCPSocketAddress.new(unsquare.call(host), port)
        end
      when Hash
        if (type = config[:type] || config['type']) then
          case (type.to_s)
          when 'tcp'
            host = config[:host] || config['host']
            port = config[:port] || config['port']
            if (host && (host.is_a? String) && port && (port.is_a? Integer)) then
              return TCPSocketAddress.new(unsquare.call(host), port)
            end
          when 'unix'
            path = config[:path] || config['path']
            if (path && (path.is_a? String) && ! path.empty?) then
              return UNIXSocketAddress.new(path)
            end
          end
        end
      end

      return
    end
  end

  class TCPSocketAddress < SocketAddress
    def initialize(host, port)
      super(:tcp)
      @host = host
      @port = port
    end

    attr_reader :host
    attr_reader :port

    def to_a
      super << @host <<  @port
    end

    def open_server
      TCPServer.new(@host, @port)
    end
  end

  class UNIXSocketAddress < SocketAddress
    def initialize(path)
      super(:unix)
      @path = path
    end

    attr_reader :path

    def to_a
      super << @path
    end

    def open_server
      UNIXServer.new(@path)
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
      @at_stat_get = nil
      @at_stat_stop = nil
      @preprocess = nil
      @postprocess = nil
      @accept = nil
      @accept_return = nil
      @dispatch = nil
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
          @thread_num.times{|i|
            thread_list << Thread.new{
              Thread.current[:number] = i
              while (socket = queue.pop)
                begin
                  @dispatch.call(socket)
                ensure
                  socket.close unless socket.closed?
                end
              end
            }
          }

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

        @at_stop.call(@stop_state)
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
          raise "internal error: unknown stop state <#{@stop_state.inspect}>"
        end
      ensure
        @postprocess.call
      end

      nil
    end
  end

  SocketProcess = Struct.new(:pid, :io)

  class SocketProcessDispatcher
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

    SIGNAL_STOP_GRACEFUL      = 'TERM'
    SIGNAL_STOP_FORCED        = 'QUIT'
    SIGNAL_STAT_GET_AND_RESET = 'USR1'
    SIGNAL_STAT_GET_NO_RESET  = 'USR2'
    SIGNAL_STAT_STOP          = 'WINCH'

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
          thread_dispatcher.at_stat_get(&NO_CALL)
          thread_dispatcher.at_stat_stop(&NO_CALL)
          thread_dispatcher.preprocess(&@preprocess)
          thread_dispatcher.postprocess(&@postprocess)

          thread_dispatcher.accept{
            if (child_io.wait_readable(@process_send_io_polling_timeout_seconds) != nil) then
              command = child_io.read(5)
              command == "SEND\n" or raise "internal error: unknown command <#{command.inspect}>"
              child_io.recv_io(socket_class)
            end
          }
          thread_dispatcher.accept_return{ child_io.write("RADY\n") }
          thread_dispatcher.dispatch(&@dispatch)

          Signal.trap(SIGNAL_STOP_GRACEFUL) { thread_dispatcher.signal_stop_graceful }
          Signal.trap(SIGNAL_STOP_FORCED) { thread_dispatcher.signal_stop_forced }
          Signal.trap(SIGNAL_STAT_GET_AND_RESET) { thread_dispatcher.signal_stat_get(reset: true) }
          Signal.trap(SIGNAL_STAT_GET_NO_RESET) { thread_dispatcher.signal_stat_get(reset: false) }
          Signal.trap(SIGNAL_STAT_STOP) { thread_dispatcher.signal_stat_stop }

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

      @process_dispatcher = SocketThreadDispatcher.new(@process_queue_name)
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
        if (server_socket.wait_readable(@accept_polling_timeout_seconds) != nil) then
          server_socket.accept
        end
      }
      @process_dispatcher.accept_return(&NO_CALL)
      @process_dispatcher.dispatch{|socket|
        process = process_list[Thread.current[:number]]
        process.io.write("SEND\n")
        process.io.send_io(socket)
        response = process.io.read(5)
        response == "RADY\n" or raise "internal error: unknown response <#{response.inspect}>"
      }
      @process_dispatcher.start

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
      @process_send_io_polling_timeout_seconds = 0.1
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
        @dispatcher.start(server_socket)
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
          if (server_socket.wait_readable(@accept_polling_timeout_seconds) != nil) then
            server_socket.accept
          end
        }
        @dispatcher.accept_return(&NO_CALL)
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
