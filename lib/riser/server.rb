# -*- coding: utf-8 -*-

require 'thread'

module Riser
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
