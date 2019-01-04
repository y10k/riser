# -*- coding: utf-8 -*-

require 'riser'
require 'test/unit'

module Riser::Test
  class ReadPollTest < Test::Unit::TestCase
    def setup
      @dt = 0.01
      @read_io, @write_io = IO.pipe
      @read_poll = Riser::ReadPoll.new(@read_io)
    end

    def test_read_poll_data
      @write_io.syswrite("HALO\n1")

      assert_equal(@read_io, @read_poll.call(@dt))
      assert(@read_poll.interval_seconds < @dt)
      assert_equal("HALO\n", @read_io.gets)

      assert_equal(true, @read_poll.call(@dt))
      assert(@read_poll.interval_seconds < @dt)
      assert_equal('1', @read_io.read(1))

      assert_equal(nil, @read_poll.call(@dt))
      assert(@read_poll.interval_seconds >= @dt)
    end

    def test_read_poll_no_data
      assert(@read_poll.interval_seconds < @dt)
      assert_equal(nil, @read_poll.call(@dt))
      assert(@read_poll.interval_seconds >= @dt)
    end

    def test_read_poll_close
      @write_io.close

      assert_equal(@read_io, @read_poll.call(@dt))
      assert(@read_poll.interval_seconds < @dt)
      assert_equal("", @read_io.read)

      assert_equal(@read_io, @read_poll.call(@dt))
      assert(@read_poll.interval_seconds < @dt)
      assert_equal(nil, @read_io.gets)

      assert_equal(@read_io, @read_poll.call(@dt))
      assert(@read_poll.interval_seconds < @dt)
      assert_raise(EOFError) { @read_io.sysread(1) }
    end

    def test_reset_timer
      assert_equal(nil, @read_poll.call(@dt))
      assert(@read_poll.interval_seconds >= @dt)

      @read_poll.reset_timer
      assert(@read_poll.interval_seconds < @dt)
    end

    def teardown
      @read_io.close unless @read_io.closed?
      @write_io.close unless @write_io.closed?
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
