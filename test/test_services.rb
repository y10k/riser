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

  class DRbServicesTest < Test::Unit::TestCase
    def setup
      @druby_process_num = 8
      @services = Riser::DRbServices.new(@druby_process_num)
    end

    def test_stateless_any_process_service
      @services.add_any_process_service(:stateless, Fib)
      @services.start_server
      begin
        @services.start_client
        assert_equal(0, @services[:stateless].fib(0))
        assert_equal(1, @services[:stateless].fib(1))
        assert_equal(1, @services[:stateless].fib(2))
        assert_equal(2, @services[:stateless].fib(3))
        assert_equal(3, @services[:stateless].fib(4))
        assert_equal(5, @services[:stateless].fib(5))
        assert_equal(8, @services[:stateless].fib(6))
        assert_equal(13, @services[:stateless].fib(7))
        assert_equal(21, @services[:stateless].fib(8))
        assert_equal(34, @services[:stateless].fib(9))
        assert_equal(55, @services[:stateless].fib(10))
        assert_equal(89, @services[:stateless].fib(11))
        assert_equal(144, @services[:stateless].fib(12))
        assert_equal(233, @services[:stateless].fib(13))
        assert_equal(377, @services[:stateless].fib(14))
        assert_equal(610, @services[:stateless].fib(15))
      ensure
        @services.stop_server
      end
    end

    def test_stateless_signle_process_service
      @services.add_single_process_service(:stateless, Fib)
      @services.start_server
      begin
        @services.start_client
        assert_equal(0, @services[:stateless].fib(0))
        assert_equal(1, @services[:stateless].fib(1))
        assert_equal(1, @services[:stateless].fib(2))
        assert_equal(2, @services[:stateless].fib(3))
        assert_equal(3, @services[:stateless].fib(4))
        assert_equal(5, @services[:stateless].fib(5))
        assert_equal(8, @services[:stateless].fib(6))
        assert_equal(13, @services[:stateless].fib(7))
        assert_equal(21, @services[:stateless].fib(8))
        assert_equal(34, @services[:stateless].fib(9))
        assert_equal(55, @services[:stateless].fib(10))
        assert_equal(89, @services[:stateless].fib(11))
        assert_equal(144, @services[:stateless].fib(12))
        assert_equal(233, @services[:stateless].fib(13))
        assert_equal(377, @services[:stateless].fib(14))
        assert_equal(610, @services[:stateless].fib(15))
      ensure
        @services.stop_server
      end
    end

    def test_stateless_sticky_process_service
      @services.add_sticky_process_service(:stateless, Fib)
      @services.start_server
      begin
        @services.start_client
        assert_equal(0, @services[:stateless, 'alice'].fib(0))
        assert_equal(1, @services[:stateless, 'alice'].fib(1))
        assert_equal(1, @services[:stateless, 'alice'].fib(2))
        assert_equal(2, @services[:stateless, 'alice'].fib(3))
        assert_equal(3, @services[:stateless, 'alice'].fib(4))
        assert_equal(5, @services[:stateless, 'alice'].fib(5))
        assert_equal(8, @services[:stateless, 'alice'].fib(6))
        assert_equal(13, @services[:stateless, 'alice'].fib(7))
        assert_equal(21, @services[:stateless, 'alice'].fib(8))
        assert_equal(34, @services[:stateless, 'alice'].fib(9))
        assert_equal(55, @services[:stateless, 'alice'].fib(10))
        assert_equal(89, @services[:stateless, 'alice'].fib(11))
        assert_equal(144, @services[:stateless, 'alice'].fib(12))
        assert_equal(233, @services[:stateless, 'alice'].fib(13))
        assert_equal(377, @services[:stateless, 'alice'].fib(14))
        assert_equal(610, @services[:stateless, 'alice'].fib(15))
      ensure
        @services.stop_server
      end
    end

    def test_stateful_any_process_service_NG
      @services.add_any_process_service(:stateful, Count.new)
      @services.start_server
      begin
        @services.start_client
        100.times do
          @services[:stateful].succ!('alice')
        end
        assert(@services[:stateful].get('alice') < 100, 'Should actually be 100 but was...')
      ensure
        @services.stop_server
      end
    end

    def test_stateful_single_process_service
      @services.add_single_process_service(:stateful, Count.new)
      @services.start_server
      begin
        @services.start_client
        100.times do
          @services[:stateful].succ!('alice')
          @services[:stateful].succ!('bob')
        end
        assert_equal(100, @services[:stateful].get('alice'))
        assert_equal(100, @services[:stateful].get('bob'))
      ensure
        @services.stop_server
      end
    end

    def test_stateful_sticky_process_service
      alice = 'alice'
      bob = 'bob0'

      # to avoid stickiness key conflicts
      # (if the number of stickiness keys is sufficiently large, it
      # will be automatically randomly scattered)
      while ((alice.hash % @druby_process_num) == (bob.hash % @druby_process_num))
        bob.succ!
      end

      @services.add_sticky_process_service(:stateful, Count.new)
      @services.start_server
      begin
        @services.start_client
        100.times do
          @services[:stateful, alice].succ!('alice')
          @services[:stateful, bob].succ!('bob')
        end

        assert_equal(100, @services[:stateful, alice].get('alice'))
        assert_equal(0, @services[:stateful, alice].get('bob'))

        assert_equal(100, @services[:stateful, bob].get('bob'))
        assert_equal(0, @services[:stateful, bob].get('alice'))
      ensure
        @services.stop_server
      end
    end

    def test_block_any_process_service
      @services.add_any_process_service(:block, Repeat)
      @services.start_server
      begin
        @services.start_client
        count = 0
        @services[:block].repeat(2) { count += 1 }
        @services[:block].repeat(3) { count += 1 }
        assert_equal(5, count)
      ensure
        @services.stop_server
      end
    end

    def test_block_single_process_service
      @services.add_single_process_service(:block, Repeat)
      @services.start_server
      begin
        @services.start_client
        count = 0
        @services[:block].repeat(2) { count += 1 }
        @services[:block].repeat(3) { count += 1 }
        assert_equal(5, count)
      ensure
        @services.stop_server
      end
    end

    def test_block_sticky_process_service
      @services.add_sticky_process_service(:block, Repeat)
      @services.start_server
      begin
        @services.start_client
        count = 0
        @services[:block, 'alice'].repeat(2) { count += 1 }
        @services[:block, 'alice'].repeat(3) { count += 1 }
        assert_equal(5, count)
      ensure
        @services.stop_server
      end
    end
  end

  class LocalServicesTest < Test::Unit::TestCase
    def setup
      @services = Riser::DRbServices.new(0)
    end

    def test_stateless_any_process_service
      @services.add_any_process_service(:stateless, Fib)
      @services.start_server
      begin
        @services.start_client
        assert_equal(0, @services[:stateless].fib(0))
        assert_equal(1, @services[:stateless].fib(1))
        assert_equal(1, @services[:stateless].fib(2))
        assert_equal(2, @services[:stateless].fib(3))
        assert_equal(3, @services[:stateless].fib(4))
        assert_equal(5, @services[:stateless].fib(5))
        assert_equal(8, @services[:stateless].fib(6))
        assert_equal(13, @services[:stateless].fib(7))
        assert_equal(21, @services[:stateless].fib(8))
        assert_equal(34, @services[:stateless].fib(9))
        assert_equal(55, @services[:stateless].fib(10))
        assert_equal(89, @services[:stateless].fib(11))
        assert_equal(144, @services[:stateless].fib(12))
        assert_equal(233, @services[:stateless].fib(13))
        assert_equal(377, @services[:stateless].fib(14))
        assert_equal(610, @services[:stateless].fib(15))
      ensure
        @services.stop_server
      end
    end

    def test_stateless_signle_process_service
      @services.add_single_process_service(:stateless, Fib)
      @services.start_server
      begin
        @services.start_client
        assert_equal(0, @services[:stateless].fib(0))
        assert_equal(1, @services[:stateless].fib(1))
        assert_equal(1, @services[:stateless].fib(2))
        assert_equal(2, @services[:stateless].fib(3))
        assert_equal(3, @services[:stateless].fib(4))
        assert_equal(5, @services[:stateless].fib(5))
        assert_equal(8, @services[:stateless].fib(6))
        assert_equal(13, @services[:stateless].fib(7))
        assert_equal(21, @services[:stateless].fib(8))
        assert_equal(34, @services[:stateless].fib(9))
        assert_equal(55, @services[:stateless].fib(10))
        assert_equal(89, @services[:stateless].fib(11))
        assert_equal(144, @services[:stateless].fib(12))
        assert_equal(233, @services[:stateless].fib(13))
        assert_equal(377, @services[:stateless].fib(14))
        assert_equal(610, @services[:stateless].fib(15))
      ensure
        @services.stop_server
      end
    end

    def test_stateless_sticky_process_service
      @services.add_sticky_process_service(:stateless, Fib)
      @services.start_server
      begin
        @services.start_client
        assert_equal(0, @services[:stateless, 'alice'].fib(0))
        assert_equal(1, @services[:stateless, 'alice'].fib(1))
        assert_equal(1, @services[:stateless, 'alice'].fib(2))
        assert_equal(2, @services[:stateless, 'alice'].fib(3))
        assert_equal(3, @services[:stateless, 'alice'].fib(4))
        assert_equal(5, @services[:stateless, 'alice'].fib(5))
        assert_equal(8, @services[:stateless, 'alice'].fib(6))
        assert_equal(13, @services[:stateless, 'alice'].fib(7))
        assert_equal(21, @services[:stateless, 'alice'].fib(8))
        assert_equal(34, @services[:stateless, 'alice'].fib(9))
        assert_equal(55, @services[:stateless, 'alice'].fib(10))
        assert_equal(89, @services[:stateless, 'alice'].fib(11))
        assert_equal(144, @services[:stateless, 'alice'].fib(12))
        assert_equal(233, @services[:stateless, 'alice'].fib(13))
        assert_equal(377, @services[:stateless, 'alice'].fib(14))
        assert_equal(610, @services[:stateless, 'alice'].fib(15))
      ensure
        @services.stop_server
      end
    end

    def test_stateful_any_process_service
      @services.add_any_process_service(:stateful, Count.new)
      @services.start_server
      begin
        @services.start_client
        100.times do
          @services[:stateful].succ!('alice')
        end
        assert_equal(100, @services[:stateful].get('alice'), 'Because same process...')
      ensure
        @services.stop_server
      end
    end

    def test_stateful_single_process_service
      @services.add_single_process_service(:stateful, Count.new)
      @services.start_server
      begin
        @services.start_client
        100.times do
          @services[:stateful].succ!('alice')
          @services[:stateful].succ!('bob')
        end
        assert_equal(100, @services[:stateful].get('alice'))
        assert_equal(100, @services[:stateful].get('bob'))
      ensure
        @services.stop_server
      end
    end

    def test_stateful_sticky_process_service
      @services.add_sticky_process_service(:stateful, Count.new)
      @services.start_server
      begin
        @services.start_client
        100.times do
          @services[:stateful, 'alice'].succ!('alice')
          @services[:stateful, 'bob'].succ!('bob')
        end

        assert_equal(100, @services[:stateful, 'alice'].get('alice'))
        assert_equal(100, @services[:stateful, 'alice'].get('bob'), 'Because same process...')

        assert_equal(100, @services[:stateful, 'bob'].get('bob'))
        assert_equal(100, @services[:stateful, 'bob'].get('alice'), 'Because same process...')
      ensure
        @services.stop_server
      end
    end

    def test_block_any_process_service
      @services.add_any_process_service(:block, Repeat)
      @services.start_server
      begin
        @services.start_client
        count = 0
        @services[:block].repeat(2) { count += 1 }
        @services[:block].repeat(3) { count += 1 }
        assert_equal(5, count)
      ensure
        @services.stop_server
      end
    end

    def test_block_single_process_service
      @services.add_single_process_service(:block, Repeat)
      @services.start_server
      begin
        @services.start_client
        count = 0
        @services[:block].repeat(2) { count += 1 }
        @services[:block].repeat(3) { count += 1 }
        assert_equal(5, count)
      ensure
        @services.stop_server
      end
    end

    def test_block_sticky_process_service
      @services.add_sticky_process_service(:block, Repeat)
      @services.start_server
      begin
        @services.start_client
        count = 0
        @services[:block, 'alice'].repeat(2) { count += 1 }
        @services[:block, 'alice'].repeat(3) { count += 1 }
        assert_equal(5, count)
      ensure
        @services.stop_server
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
