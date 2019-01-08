# -*- coding: utf-8 -*-

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
