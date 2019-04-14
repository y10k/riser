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
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
