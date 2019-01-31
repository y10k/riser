# -*- coding: utf-8 -*-

require 'riser'
require 'riser/test'
require 'test/unit'

module Riser::Test
  class CallRecorderTest < Test::Unit::TestCase
    def setup
      @recorder = CallRecorder.new('recorder_test')
    end

    def teardown
      @recorder.dispose
    end

    def test_call
      assert_equal([], @recorder.get_memory_records)
      assert_equal([], @recorder.get_file_records)

      @recorder.call('a')
      assert_equal(%w[ a ], @recorder.get_memory_records)
      assert_equal(%w[ a ], @recorder.get_file_records)

      @recorder.call('b')
      @recorder.call('c')
      assert_equal(%w[ a b c ], @recorder.get_memory_records)
      assert_equal(%w[ a b c ], @recorder.get_file_records)
    end

    def test_call_fork
      fork{
        @recorder.call('a')
      }
      Process.wait

      assert_equal([], @recorder.get_memory_records)
      assert_equal(%w[ a ], @recorder.get_file_records)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
