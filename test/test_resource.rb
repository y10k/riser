# -*- coding: utf-8 -*-

require 'fileutils'
require 'riser'
require 'riser/test'
require 'test/unit'

module Riser::Test
  class ResurceTest < Test::Unit::TestCase
    def setup
      @build = Riser::Resource::Builder.new
      @store_path = 'resource_test'
      @recorder = CallRecorder.new(@store_path)
    end

    def teardown
      FileUtils.rm_f(@store_path)
    end

    def test_resource
      @build.at_create{
        @recorder.call('at_create')
        Array.new
      }
      @build.at_destroy{
        @recorder.call('at_destroy')
      }
      resource = @build.call

      assert_equal([], @recorder.get_memory_records)
      assert_equal(0, resource.ref_count)
      assert_equal(0, resource.proxy_count)
      assert_equal(false, resource.ref_object?)

      resource.call{|array|
        assert_equal(%w[ at_create ], @recorder.get_memory_records)
        assert_equal(1, resource.ref_count)
        assert_equal(1, resource.proxy_count)
        assert_equal(true, resource.ref_object?)

        assert_equal(0, array.length)

        array << :foo
        array << :bar
        array << :baz

        assert_equal(3, array.length)
        assert_equal(:foo, array[0])
        assert_equal(:bar, array[1])
        assert_equal(:baz, array[2])
      }

      assert_equal(%w[ at_create at_destroy ], @recorder.get_memory_records)
      assert_equal(0, resource.ref_count)
      assert_equal(0, resource.proxy_count)
      assert_equal(false, resource.ref_object?)
    end

    def test_resource_alias_unref
      @build.at_create{
        @recorder.call('at_create')
        Array.new
      }
      @build.at_destroy{
        @recorder.call('at_destroy')
      }
      @build.alias_unref(:close)
      resource = @build.call

      assert_equal([], @recorder.get_memory_records)
      assert_equal(0, resource.ref_count)
      assert_equal(0, resource.proxy_count)
      assert_equal(false, resource.ref_object?)

      array = resource.call
      assert_equal(%w[ at_create ], @recorder.get_memory_records)
      assert_equal(1, resource.ref_count)
      assert_equal(1, resource.proxy_count)
      assert_equal(true, resource.ref_object?)

      assert_equal(0, array.length)

      array << :foo
      array << :bar
      array << :baz

      assert_equal(3, array.length)
      assert_equal(:foo, array[0])
      assert_equal(:bar, array[1])
      assert_equal(:baz, array[2])

      assert_respond_to(array, :close)
      array.close
      assert_equal(%w[ at_create at_destroy ], @recorder.get_memory_records)
      assert_equal(0, resource.ref_count)
      assert_equal(0, resource.proxy_count)
      assert_equal(false, resource.ref_object?)
    end

    def test_resource_overlap
      @build.at_create{
        @recorder.call('at_create')
        Array.new
      }
      @build.at_destroy{
        @recorder.call('at_destroy')
      }
      resource = @build.call

      assert_equal([], @recorder.get_memory_records)
      assert_equal(0, resource.ref_count)
      assert_equal(0, resource.proxy_count)
      assert_equal(false, resource.ref_object?)

      array_1 = resource.call
      assert_equal(%w[ at_create ], @recorder.get_memory_records)
      assert_equal(1, resource.ref_count)
      assert_equal(1, resource.proxy_count)
      assert_equal(true, resource.ref_object?)

      assert_equal(0, array_1.length)

      array_2 = resource.call
      assert_equal(%w[ at_create ], @recorder.get_memory_records)
      assert_equal(2, resource.ref_count)
      assert_equal(2, resource.proxy_count)
      assert_equal(true, resource.ref_object?)

      assert_equal(0, array_2.length)

      array_1 << :foo
      array_1 << :bar
      array_1 << :baz

      assert_equal(3, array_2.length)
      assert_equal(:foo, array_2[0])
      assert_equal(:bar, array_2[1])
      assert_equal(:baz, array_2[2])

      array_1.__unref__
      assert_equal(%w[ at_create ], @recorder.get_memory_records)
      assert_equal(1, resource.ref_count)
      assert_equal(1, resource.proxy_count)
      assert_equal(true, resource.ref_object?)

      assert_equal(3, array_2.length)
      assert_equal(:foo, array_2[0])
      assert_equal(:bar, array_2[1])
      assert_equal(:baz, array_2[2])

      array_2.__unref__
      assert_equal(%w[ at_create at_destroy ], @recorder.get_memory_records)
      assert_equal(0, resource.ref_count)
      assert_equal(0, resource.proxy_count)
      assert_equal(false, resource.ref_object?)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
