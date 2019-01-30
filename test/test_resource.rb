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

  class ResourceSetTest < Test::Unit::TestCase
    def setup
      @build = Riser::ResourceSet::Builder.new
      @store_path = 'resource_set_test'
      @recorder = CallRecorder.new(@store_path)
    end

    def teardown
      FileUtils.rm_f(@store_path)
    end

    def test_resource_set
      @build.at_create{|key|
        @recorder.call("at_create:#{key}")
        Array[key]
      }
      @build.at_destroy{|a|
        @recorder.call("at_destroy:#{a[0]}")
      }
      resource_set = @build.call

      assert_equal([], @recorder.get_memory_records)
      assert_equal(0, resource_set.key_count)
      assert_equal(0, resource_set.ref_count('alice'))
      assert_equal(0, resource_set.proxy_count)
      assert_equal(false, (resource_set.ref_object? 'alice'))

      resource_set.call('alice') {|alice|
        assert_equal(%w[ at_create:alice ], @recorder.get_memory_records)
        assert_equal(1, resource_set.key_count)
        assert_equal(1, resource_set.ref_count('alice'))
        assert_equal(1, resource_set.proxy_count)
        assert_equal(true, (resource_set.ref_object? 'alice'))

        assert_equal(1, alice.length)
        assert_equal('alice', alice[0])
      }

      assert_equal(%w[ at_create:alice at_destroy:alice ], @recorder.get_memory_records)
      assert_equal(0, resource_set.key_count)
      assert_equal(0, resource_set.ref_count('alice'))
      assert_equal(0, resource_set.proxy_count)
      assert_equal(false, (resource_set.ref_object? 'alice'))
    end

    def test_resource_set_alias_unref
      @build.at_create{|key|
        @recorder.call("at_create:#{key}")
        Array[key]
      }
      @build.at_destroy{|a|
        @recorder.call("at_destroy:#{a[0]}")
      }
      @build.alias_unref(:close)
      resource_set = @build.call

      assert_equal([], @recorder.get_memory_records)
      assert_equal(0, resource_set.key_count)
      assert_equal(0, resource_set.ref_count('alice'))
      assert_equal(0, resource_set.proxy_count)
      assert_equal(false, (resource_set.ref_object? 'alice'))

      alice = resource_set.call('alice')
      assert_equal(%w[ at_create:alice ], @recorder.get_memory_records)
      assert_equal(1, resource_set.key_count)
      assert_equal(1, resource_set.ref_count('alice'))
      assert_equal(1, resource_set.proxy_count)
      assert_equal(true, (resource_set.ref_object? 'alice'))

      assert_equal(1, alice.length)
      assert_equal('alice', alice[0])

      assert_respond_to(alice, :close)
      alice.close
      assert_equal(%w[ at_create:alice at_destroy:alice ], @recorder.get_memory_records)
      assert_equal(0, resource_set.key_count)
      assert_equal(0, resource_set.ref_count('alice'))
      assert_equal(0, resource_set.proxy_count)
      assert_equal(false, (resource_set.ref_object? 'alice'))
    end

    def test_resource_set_overlap
      @build.at_create{|key|
        @recorder.call("at_create:#{key}")
        Array[key]
      }
      @build.at_destroy{|a|
        @recorder.call("at_destroy:#{a[0]}")
      }
      resource_set = @build.call

      assert_equal([], @recorder.get_memory_records)
      assert_equal(0, resource_set.key_count)
      assert_equal(0, resource_set.ref_count('alice'))
      assert_equal(0, resource_set.ref_count('bob'))
      assert_equal(0, resource_set.proxy_count)
      assert_equal(false, (resource_set.ref_object? 'alice'))
      assert_equal(false, (resource_set.ref_object? 'bob'))

      alice_1 = resource_set.call('alice')
      assert_equal(%w[ at_create:alice ], @recorder.get_memory_records)
      assert_equal(1, resource_set.key_count)
      assert_equal(1, resource_set.ref_count('alice'))
      assert_equal(0, resource_set.ref_count('bob'))
      assert_equal(1, resource_set.proxy_count)
      assert_equal(true,  (resource_set.ref_object? 'alice'))
      assert_equal(false, (resource_set.ref_object? 'bob'))

      assert_equal(1, alice_1.length)
      assert_equal('alice', alice_1[0])

      alice_2 = resource_set.call('alice')
      assert_equal(%w[ at_create:alice ], @recorder.get_memory_records)
      assert_equal(1, resource_set.key_count)
      assert_equal(2, resource_set.ref_count('alice'))
      assert_equal(0, resource_set.ref_count('bob'))
      assert_equal(2, resource_set.proxy_count)
      assert_equal(true,  (resource_set.ref_object? 'alice'))
      assert_equal(false, (resource_set.ref_object? 'bob'))

      assert_equal(1, alice_2.length)
      assert_equal('alice', alice_2[0])

      alice_1 << :foo
      alice_1 << :bar

      assert_equal(3, alice_2.length)
      assert_equal('alice', alice_2[0])
      assert_equal(:foo,    alice_2[1])
      assert_equal(:bar,    alice_2[2])

      bob = resource_set.call('bob')
      assert_equal(%w[ at_create:alice at_create:bob ], @recorder.get_memory_records)
      assert_equal(2, resource_set.key_count)
      assert_equal(2, resource_set.ref_count('alice'))
      assert_equal(1, resource_set.ref_count('bob'))
      assert_equal(3, resource_set.proxy_count)
      assert_equal(true, (resource_set.ref_object? 'alice'))
      assert_equal(true, (resource_set.ref_object? 'bob'))

      assert_equal(1, bob.length)
      assert_equal('bob', bob[0])

      alice_1.__unref__
      assert_equal(%w[ at_create:alice at_create:bob ], @recorder.get_memory_records)
      assert_equal(2, resource_set.key_count)
      assert_equal(1, resource_set.ref_count('alice'))
      assert_equal(1, resource_set.ref_count('bob'))
      assert_equal(2, resource_set.proxy_count)
      assert_equal(true, (resource_set.ref_object? 'alice'))
      assert_equal(true, (resource_set.ref_object? 'bob'))

      assert_equal(3, alice_2.length)
      assert_equal('alice', alice_2[0])
      assert_equal(:foo,    alice_2[1])
      assert_equal(:bar,    alice_2[2])

      alice_2.__unref__
      assert_equal(%w[ at_create:alice at_create:bob at_destroy:alice ], @recorder.get_memory_records)
      assert_equal(1, resource_set.key_count)
      assert_equal(0, resource_set.ref_count('alice'))
      assert_equal(1, resource_set.ref_count('bob'))
      assert_equal(1, resource_set.proxy_count)
      assert_equal(false, (resource_set.ref_object? 'alice'))
      assert_equal(true,  (resource_set.ref_object? 'bob'))

      assert_equal(1, bob.length)
      assert_equal('bob', bob[0])

      bob.__unref__
      assert_equal(%w[ at_create:alice at_create:bob at_destroy:alice at_destroy:bob ], @recorder.get_memory_records)
      assert_equal(0, resource_set.key_count)
      assert_equal(0, resource_set.ref_count('alice'))
      assert_equal(0, resource_set.ref_count('bob'))
      assert_equal(0, resource_set.proxy_count)
      assert_equal(false, (resource_set.ref_object? 'alice'))
      assert_equal(false, (resource_set.ref_object? 'bob'))
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
