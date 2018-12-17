# -*- coding: utf-8 -*-

require 'riser'
require 'test/unit'
require 'thread'

module Riser::Test
  module Fib
    def fib(n)
      if (n < 2) then
        n
      else
        fib(n - 1) + fib(n - 2)
      end
    end
    module_function :fib
  end

  class Count
    def initialize
      @mutex = Mutex.new
      @count = Hash.new(0)
    end

    def succ!(user)
      @mutex.synchronize{
        @count[user] += 1
      }
    end

    def get(user)
      @mutex.synchronize{
        @count[user]
      }
    end
  end

  module Repeat
    def repeat(num)
      num.times do
        yield
      end
    end
    module_function :repeat
  end

  class DRbServiceServerCallTest < Test::Unit::TestCase
    def setup
      @call = Riser::DRbServiceCall.new
      @server = Riser::DRbServiceServer.new
      @server.add_service(:stateless, Fib)
      @server.add_service(:stateful, Count.new)
      @server.add_service(:block, Repeat)

      @drb_proc_num = 8
      @drb_proc_num.times do
        uri = Riser.make_drbunix_uri
        @call.add_druby_call(uri)
        @server.add_druby_process(uri, UNIXFileMode: 0600)
      end

      @server.start
    end

    def teardown
      @server.stop
    end

    def test_stateless_any_process_service
      @call.add_any_process_service(:stateless)
      @call.start
      assert_equal(0, @call[:stateless].fib(0))
      assert_equal(1, @call[:stateless].fib(1))
      assert_equal(1, @call[:stateless].fib(2))
      assert_equal(2, @call[:stateless].fib(3))
      assert_equal(3, @call[:stateless].fib(4))
      assert_equal(5, @call[:stateless].fib(5))
      assert_equal(8, @call[:stateless].fib(6))
      assert_equal(13, @call[:stateless].fib(7))
      assert_equal(21, @call[:stateless].fib(8))
      assert_equal(34, @call[:stateless].fib(9))
      assert_equal(55, @call[:stateless].fib(10))
      assert_equal(89, @call[:stateless].fib(11))
      assert_equal(144, @call[:stateless].fib(12))
      assert_equal(233, @call[:stateless].fib(13))
      assert_equal(377, @call[:stateless].fib(14))
      assert_equal(610, @call[:stateless].fib(15))
    end

    def test_stateless_single_process_service
      @call.add_single_process_service(:stateless)
      @call.start
      assert_equal(0, @call[:stateless].fib(0))
      assert_equal(1, @call[:stateless].fib(1))
      assert_equal(1, @call[:stateless].fib(2))
      assert_equal(2, @call[:stateless].fib(3))
      assert_equal(3, @call[:stateless].fib(4))
      assert_equal(5, @call[:stateless].fib(5))
      assert_equal(8, @call[:stateless].fib(6))
      assert_equal(13, @call[:stateless].fib(7))
      assert_equal(21, @call[:stateless].fib(8))
      assert_equal(34, @call[:stateless].fib(9))
      assert_equal(55, @call[:stateless].fib(10))
      assert_equal(89, @call[:stateless].fib(11))
      assert_equal(144, @call[:stateless].fib(12))
      assert_equal(233, @call[:stateless].fib(13))
      assert_equal(377, @call[:stateless].fib(14))
      assert_equal(610, @call[:stateless].fib(15))
    end

    def test_stateless_sticky_process_service
      @call.add_sticky_process_service(:stateless)
      @call.start
      assert_equal(0, @call[:stateless, 'alice'].fib(0))
      assert_equal(1, @call[:stateless, 'alice'].fib(1))
      assert_equal(1, @call[:stateless, 'alice'].fib(2))
      assert_equal(2, @call[:stateless, 'alice'].fib(3))
      assert_equal(3, @call[:stateless, 'alice'].fib(4))
      assert_equal(5, @call[:stateless, 'alice'].fib(5))
      assert_equal(8, @call[:stateless, 'alice'].fib(6))
      assert_equal(13, @call[:stateless, 'alice'].fib(7))
      assert_equal(21, @call[:stateless, 'alice'].fib(8))
      assert_equal(34, @call[:stateless, 'alice'].fib(9))
      assert_equal(55, @call[:stateless, 'alice'].fib(10))
      assert_equal(89, @call[:stateless, 'alice'].fib(11))
      assert_equal(144, @call[:stateless, 'alice'].fib(12))
      assert_equal(233, @call[:stateless, 'alice'].fib(13))
      assert_equal(377, @call[:stateless, 'alice'].fib(14))
      assert_equal(610, @call[:stateless, 'alice'].fib(15))
    end

    def test_stateful_any_process_service_NG
      @call.add_any_process_service(:stateful)
      @call.start
      100.times do
        @call[:stateful].succ!('alice')
      end
      assert(@call[:stateful].get('alice') < 100, 'Should actually be 100 but was...')
    end

    def test_stateful_single_process_service
      @call.add_single_process_service(:stateful)
      @call.start
      100.times do
        @call[:stateful].succ!('alice')
        @call[:stateful].succ!('bob')
      end
      assert_equal(100, @call[:stateful].get('alice'))
      assert_equal(100, @call[:stateful].get('bob'))
    end

    def test_stateful_sticky_process_service
      alice = 'alice'
      bob = 'bob0'

      # to avoid stickiness key conflicts
      # (if the number of stickiness keys is sufficiently large, it
      # will be automatically randomly scattered)
      while ((alice.hash % @drb_proc_num) == (bob.hash % @drb_proc_num))
        bob.succ!
      end

      @call.add_sticky_process_service(:stateful)
      @call.start
      100.times do
        @call[:stateful, alice].succ!('alice')
        @call[:stateful, bob].succ!('bob')
      end

      assert_equal(100, @call[:stateful, alice].get('alice'))
      assert_equal(0, @call[:stateful, alice].get('bob'))

      assert_equal(100, @call[:stateful, bob].get('bob'))
      assert_equal(0, @call[:stateful, bob].get('alice'))
    end

    def test_block_any_process_service
      @call.add_any_process_service(:block)
      @call.start
      count = 0
      @call[:block].repeat(2) { count += 1 }
      @call[:block].repeat(3) { count += 1 }
      assert_equal(5, count)
    end

    def test_block_single_process_service
      @call.add_single_process_service(:block)
      @call.start
      count = 0
      @call[:block].repeat(2) { count += 1 }
      @call[:block].repeat(3) { count += 1 }
      assert_equal(5, count)
    end

    def test_block_sticky_process_service
      @call.add_sticky_process_service(:block)
      @call.start
      count = 0
      @call[:block, 'alice'].repeat(2) { count += 1 }
      @call[:block, 'alice'].repeat(3) { count += 1 }
      assert_equal(5, count)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
