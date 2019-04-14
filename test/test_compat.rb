# -*- coding: utf-8 -*-

require 'riser'
require 'test/unit'

module Riser::Test
  class TestCompatibleStringIO < Test::Unit::TestCase
    using Riser::CompatibleStringIO

    def setup
      @s = StringIO.new('foo')
    end

    def test_to_io
      assert_equal(@s, @s.to_io)
    end

    def test_to_i
      assert_kind_of(Integer, @s.to_i)
    end

    def test_wait_readable
      assert_equal(false, @s.eof?)
      assert_equal(true, @s.wait_readable(1))
    end

    def test_wait_readable_eof
      @s.read
      assert_equal(true, @s.eof?)
      assert_equal(false, @s.wait_readable(1))
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
