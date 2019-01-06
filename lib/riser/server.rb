# -*- coding: utf-8 -*-

require 'thread'

module Riser
  class TimeoutSizedQueue
    # When the queue is processed at high speed without staying, it is
    # better to set the queue size to about 10 times the number of
    # waiting threads in order to increase the queue throughput. If
    # queue staying time is long, it is better to set a small queue
    # size so that you do not want to queue data at long time.
    def initialize(size)
      @size = size
      @queue = []
      @closed = false
      @mutex = Mutex.new
      @push_cond = ConditionVariable.new
      @pop_cond = ConditionVariable.new
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
        unless (@queue.size < @size) then
          @push_cond.wait(@mutex, timeout_seconds)
          unless (@queue.size < @size) then
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
        while (@queue.empty?)
          @closed and return
          @pop_cond.wait(@mutex)
        end
        @push_cond.signal
        @queue.shift
      }
    end
  end

  class PullBuffer
    def initialize
      @mutex = Mutex.new
      @closed = false
      @value = []               # the state should be empty or only one element
      @pull_count = 0
      @pull_cond = ConditionVariable.new
      @push_ready_cond = ConditionVariable.new
    end

    # should be executed when `push_ready?' is true
    def close
      @mutex.synchronize{ @closed = true }
      nil
    end

    def closed?
      @mutex.synchronize{ @closed }
    end

    def at_end_of_buffer?
      @mutex.synchronize{ @closed && @value.size == 0 }
    end

    # should be repeat to try
    def pull(timeout_seconds)
      value = nil
      @mutex.synchronize{
        @pull_count += 1
        begin
          @push_ready_cond.signal
          if (@value.size == 0) then
            @closed and return
            @pull_cond.wait(@mutex, timeout_seconds)
            if (@value.size == 0) then
              return
            end
          end
          value = @value.pop
        ensure
          @pull_count -= 1
        end
      }

      value
    end

    # should be repeat to try
    def push_ready?(timeout_seconds)
      @mutex.synchronize{
        @closed and raise 'closed'
        @pull_count > 0 && @value.size == 0 and return true
        @push_ready_cond.wait(@mutex, timeout_seconds)
        @pull_count > 0 && @value.size == 0
      }
    end

    def push(value)
      @mutex.synchronize{
        @closed and raise 'closed'
        if (@value.size != 0) then
          raise 'not ready to push'
        end
        @value.push(value)
        @pull_cond.signal
      }

      nil
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
