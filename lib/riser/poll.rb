# -*- coding: utf-8 -*-

require 'io/wait'
require 'stringio'

module Riser
  class ReadPoll
    using CompatibleStringIO

    def initialize(read_io)
      @read_io = read_io
      reset_timer
    end

    def reset_timer
      @t0 = Time.now
      self
    end

    def interval_seconds
      Time.now - @t0
    end

    def read_poll(timeout_seconds)
      readable = @read_io.wait_readable(timeout_seconds)
      reset_timer unless readable.nil?
      readable
    end

    alias poll read_poll
    alias call read_poll
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
