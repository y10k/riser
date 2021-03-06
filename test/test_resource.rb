# -*- coding: utf-8 -*-

require 'riser'
require 'riser/test'
require 'test/unit'

module Riser::Test
  class ResurceTest < Test::Unit::TestCase
    def setup
      @recorder = CallRecorder.new('resource_test')
    end

    def teardown
      @recorder.dispose
    end

    def make_resource(at_create: -> { Array.new }, at_destroy: ->(obj) {}, unref_alias: nil)
      Riser::Resource.build{|builder|
        builder.at_create{
          @recorder.call('at_create')
          at_create.call
        }

        builder.at_destroy{|obj|
          @recorder.call('at_destroy')
          at_destroy.call(obj)
        }

        if (unref_alias) then
          builder.alias_unref(unref_alias)
        end
      }
    end
    private :make_resource

    def test_resource
      resource = make_resource

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

    def test_resource_unref_dup
      resource = make_resource

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

      array.__unref__
      assert_equal(%w[ at_create at_destroy ], @recorder.get_memory_records)
      assert_equal(0, resource.ref_count)
      assert_equal(0, resource.proxy_count)
      assert_equal(false, resource.ref_object?)

      array.__unref__           # no effect
      assert_equal(%w[ at_create at_destroy ], @recorder.get_memory_records)
      assert_equal(0, resource.ref_count)
      assert_equal(0, resource.proxy_count)
      assert_equal(false, resource.ref_object?)
    end

    def test_resource_alias_unref
      resource = make_resource(unref_alias: :close)

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
      resource = make_resource

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

    def test_resource_create_fail
      resource = make_resource(at_create: -> { raise 'abort' })

      assert_equal([], @recorder.get_memory_records)
      assert_equal(0, resource.ref_count)
      assert_equal(0, resource.proxy_count)
      assert_equal(false, resource.ref_object?)

      error = assert_raise(RuntimeError) { resource.call }
      assert_equal('abort', error.message)
      assert_equal(%w[ at_create ], @recorder.get_memory_records)
      assert_equal(0, resource.ref_count)
      assert_equal(0, resource.proxy_count)
      assert_equal(false, resource.ref_object?)
    end

    def test_resource_destroy_fail
      resource = make_resource(at_destroy: -> (obj) { raise 'abort' })

      assert_equal([], @recorder.get_memory_records)
      assert_equal(0, resource.ref_count)
      assert_equal(0, resource.proxy_count)
      assert_equal(false, resource.ref_object?)

      array = resource.call
      assert_equal(%w[ at_create ], @recorder.get_memory_records)
      assert_equal(1, resource.ref_count)
      assert_equal(1, resource.proxy_count)
      assert_equal(true, resource.ref_object?)

      error = assert_raise(RuntimeError) { array.__unref__ }
      assert_equal('abort', error.message)
      assert_equal(%w[ at_create at_destroy ], @recorder.get_memory_records)
      assert_equal(0, resource.ref_count)
      assert_equal(0, resource.proxy_count)
      assert_equal(false, resource.ref_object?)

      error = assert_raise(ArgumentError) { array.__getobj__ }
      assert_match(/not delegated/, error.message)
    end

    class KeywordArgumentExample
      def foo(bar: 'baz')
      end
    end

    # no warning messages?
    def test_resouce_proxy_keyword_argument_forwarding
      resource = make_resource(at_create: -> { KeywordArgumentExample.new })
      resource.call{|kw_args|
        kw_args.foo(bar: 'test')
      }
    end
  end

  class ResourceSetTest < Test::Unit::TestCase
    def setup
      @recorder = CallRecorder.new('resource_set_test')
    end

    def teardown
      @recorder.dispose
    end

    def make_resource_set(at_create: ->(key) { Array[key] }, at_destroy: ->(obj) {}, unref_alias: nil)
      Riser::ResourceSet.build{|builder|
        builder.at_create{|key|
          @recorder.call("at_create:#{key}")
          at_create.call(key)
        }

        builder.at_destroy{|obj|
          @recorder.call((obj.is_a? Array) ? "at_destroy:#{obj[0]}" : 'at_destroy')
          at_destroy.call(obj)
        }

        if (unref_alias) then
          builder.alias_unref(unref_alias)
        end
      }
    end

    def test_resource_set
      resource_set = make_resource_set

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

    def test_resource_set_unref_dup
      resource_set = make_resource_set

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

      alice.__unref__
      assert_equal(%w[ at_create:alice at_destroy:alice ], @recorder.get_memory_records)
      assert_equal(0, resource_set.key_count)
      assert_equal(0, resource_set.ref_count('alice'))
      assert_equal(0, resource_set.proxy_count)
      assert_equal(false, (resource_set.ref_object? 'alice'))

      alice.__unref__           # no effect
      assert_equal(%w[ at_create:alice at_destroy:alice ], @recorder.get_memory_records)
      assert_equal(0, resource_set.key_count)
      assert_equal(0, resource_set.ref_count('alice'))
      assert_equal(0, resource_set.proxy_count)
      assert_equal(false, (resource_set.ref_object? 'alice'))
    end

    def test_resource_set_alias_unref
      resource_set = make_resource_set(unref_alias: :close)

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
      resource_set = make_resource_set

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

    def test_resource_create_fail
      resource_set = make_resource_set(at_create: ->(key) { raise 'abort' })

      assert_equal([], @recorder.get_memory_records)
      assert_equal(0, resource_set.key_count)
      assert_equal(0, resource_set.ref_count('alice'))
      assert_equal(0, resource_set.proxy_count)
      assert_equal(false, (resource_set.ref_object? 'alice'))

      error = assert_raise(RuntimeError) { resource_set.call('alice') }
      assert_equal('abort', error.message)
      assert_equal(%w[ at_create:alice ], @recorder.get_memory_records)
      assert_equal(0, resource_set.key_count)
      assert_equal(0, resource_set.ref_count('alice'))
      assert_equal(0, resource_set.proxy_count)
      assert_equal(false, (resource_set.ref_object? 'alice'))
    end

    def test_resource_destroy_fail
      resource_set = make_resource_set(at_destroy: ->(obj) { raise 'abort' })

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

      error = assert_raise(RuntimeError) { alice.__unref__ }
      assert_equal('abort', error.message)
      assert_equal(%w[ at_create:alice at_destroy:alice ], @recorder.get_memory_records)
      assert_equal(0, resource_set.key_count)
      assert_equal(0, resource_set.ref_count('alice'))
      assert_equal(0, resource_set.proxy_count)
      assert_equal(false, (resource_set.ref_object? 'alice'))

      error = assert_raise(ArgumentError) { alice.__getobj__ }
      assert_match(/not delegated/, error.message)
    end

    class KeywordArgumentExample
      def foo(bar: 'baz')
      end
    end

    # no warning messages?
    def test_resouce_proxy_keyword_argument_forwarding
      resource_set = make_resource_set(at_create: ->(key) { KeywordArgumentExample.new })
      resource_set.call('alice') {|kw_args|
        kw_args.foo(bar: 'test')
      }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
