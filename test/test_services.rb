# -*- coding: utf-8 -*-

require 'riser'
require 'riser/test'
require 'test/unit'

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
      @mutex = Thread::Mutex.new
      @count = Hash.new(0)
    end

    def succ!(user)
      count = @mutex.synchronize{
        @count[user] += 1
      }
      if (block_given?) then
        yield(count)
      else
        count
      end
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

  class DRbServiceCallTest < Test::Unit::TestCase
    data('class:Proc'      => Proc,
         'class:Method'    => Method,
         'instance:proc'   => proc{},
         'instance:lambda' => lambda{},
         'instance:method' => Object.new.method(:inspect))
    def test_is_callable(data)
      assert_equal(true, Riser::DRbServiceCall.is_callable(data))
    end

    data('class:Object'    => Object,
         'instance:object' => Object.new)
    def test_is_not_callable(data)
      assert_equal(false, Riser::DRbServiceCall.is_callable(data))
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
        assert_equal(0,   @services[:stateless].fib(0))
        assert_equal(1,   @services[:stateless].fib(1))
        assert_equal(1,   @services[:stateless].fib(2))
        assert_equal(2,   @services[:stateless].fib(3))
        assert_equal(3,   @services[:stateless].fib(4))
        assert_equal(5,   @services[:stateless].fib(5))
        assert_equal(8,   @services[:stateless].fib(6))
        assert_equal(13,  @services[:stateless].fib(7))
        assert_equal(21,  @services[:stateless].fib(8))
        assert_equal(34,  @services[:stateless].fib(9))
        assert_equal(55,  @services[:stateless].fib(10))
        assert_equal(89,  @services[:stateless].fib(11))
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
        assert_equal(0,   @services[:stateless].fib(0))
        assert_equal(1,   @services[:stateless].fib(1))
        assert_equal(1,   @services[:stateless].fib(2))
        assert_equal(2,   @services[:stateless].fib(3))
        assert_equal(3,   @services[:stateless].fib(4))
        assert_equal(5,   @services[:stateless].fib(5))
        assert_equal(8,   @services[:stateless].fib(6))
        assert_equal(13,  @services[:stateless].fib(7))
        assert_equal(21,  @services[:stateless].fib(8))
        assert_equal(34,  @services[:stateless].fib(9))
        assert_equal(55,  @services[:stateless].fib(10))
        assert_equal(89,  @services[:stateless].fib(11))
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
        assert_equal(0,   @services[:stateless, 'alice'].fib(0))
        assert_equal(1,   @services[:stateless, 'alice'].fib(1))
        assert_equal(1,   @services[:stateless, 'alice'].fib(2))
        assert_equal(2,   @services[:stateless, 'alice'].fib(3))
        assert_equal(3,   @services[:stateless, 'alice'].fib(4))
        assert_equal(5,   @services[:stateless, 'alice'].fib(5))
        assert_equal(8,   @services[:stateless, 'alice'].fib(6))
        assert_equal(13,  @services[:stateless, 'alice'].fib(7))
        assert_equal(21,  @services[:stateless, 'alice'].fib(8))
        assert_equal(34,  @services[:stateless, 'alice'].fib(9))
        assert_equal(55,  @services[:stateless, 'alice'].fib(10))
        assert_equal(89,  @services[:stateless, 'alice'].fib(11))
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

    def test_procedure_any_process_service
      @services.add_any_process_service(:fib, proc{|n| Fib.fib(n) })
      @services.start_server
      begin
        @services.start_client
        assert_equal(0,   @services[:fib, 0])
        assert_equal(1,   @services[:fib, 1])
        assert_equal(1,   @services[:fib, 2])
        assert_equal(2,   @services[:fib, 3])
        assert_equal(3,   @services[:fib, 4])
        assert_equal(5,   @services[:fib, 5])
        assert_equal(8,   @services[:fib, 6])
        assert_equal(13,  @services[:fib, 7])
        assert_equal(21,  @services[:fib, 8])
        assert_equal(34,  @services[:fib, 9])
        assert_equal(55,  @services[:fib, 10])
        assert_equal(89,  @services[:fib, 11])
        assert_equal(144, @services[:fib, 12])
        assert_equal(233, @services[:fib, 13])
        assert_equal(377, @services[:fib, 14])
        assert_equal(610, @services[:fib, 15])
      ensure
        @services.stop_server
      end
    end

    def test_procedure_single_process_service
      @services.add_single_process_service(:succ!, Count.new.method(:succ!))
      @services.start_server
      begin
        @services.start_client

        assert_equal(1, @services[:succ!, 'alice'])
        assert_equal(2, @services[:succ!, 'alice'])
        assert_equal(3, @services[:succ!, 'alice'])

        assert_equal(1, @services[:succ!, 'bob'])
        assert_equal(2, @services[:succ!, 'bob'])

        assert_equal(4, @services[:succ!, 'alice'])
        assert_equal(5, @services[:succ!, 'alice'])
      ensure
        @services.stop_server
      end
    end

    def test_procedure_sticky_process_service
      @services.add_sticky_process_service(:succ!, Count.new.method(:succ!))
      @services.start_server
      begin
        @services.start_client

        assert_equal(1, @services[:succ!, 'alice'])
        assert_equal(2, @services[:succ!, 'alice'])
        assert_equal(3, @services[:succ!, 'alice'])

        assert_equal(1, @services[:succ!, 'bob'])
        assert_equal(2, @services[:succ!, 'bob'])

        assert_equal(4, @services[:succ!, 'alice'])
        assert_equal(5, @services[:succ!, 'alice'])
      ensure
        @services.stop_server
      end
    end

    def test_procedure_block_any_process_service
      @services.add_any_process_service(:repeat, Repeat.method(:repeat))
      @services.start_server
      begin
        @services.start_client
        count = 0
        @services[:repeat, 2] { count += 1 }
        @services[:repeat, 3] { count += 1 }
        assert_equal(5, count)
      ensure
        @services.stop_server
      end
    end

    def test_procedure_block_single_process_service
      @services.add_single_process_service(:succ!, Count.new.method(:succ!))
      @services.start_server
      begin
        @services.start_client
        calls = 0

        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(1, count)
        }
        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(2, count)
        }
        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(3, count)
        }

        @services[:succ!, 'bob'] {|count|
          calls += 1
          assert_equal(1, count)
        }
        @services[:succ!, 'bob'] {|count|
          calls += 1
          assert_equal(2, count)
        }

        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(4, count)
        }
        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(5, count)
        }

        assert_equal(7, calls)
      ensure
        @services.stop_server
      end
    end

    def test_procedure_block_sticky_process_service
      @services.add_sticky_process_service(:succ!, Count.new.method(:succ!))
      @services.start_server
      begin
        @services.start_client
        calls = 0

        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(1, count)
        }
        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(2, count)
        }
        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(3, count)
        }

        @services[:succ!, 'bob'] {|count|
          calls += 1
          assert_equal(1, count)
        }
        @services[:succ!, 'bob'] {|count|
          calls += 1
          assert_equal(2, count)
        }

        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(4, count)
        }
        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(5, count)
        }

        assert_equal(7, calls)
      ensure
        @services.stop_server
      end
    end
  end

  class DRbServicesConfigTest < Test::Unit::TestCase
    def make_drb_services(server_config: {}, client_config: {})
      if ($DEBUG) then
        server_config[:verbose] = true
        client_config[:verbose] = true
      end

      services = Riser::DRbServices.new(1, server_config: server_config, client_config: client_config)
      services.add_any_process_service(:put, proc{|string| })
      services.add_any_process_service(:get, proc{|size| ' ' * size })

      # eliminate the effects of previous tests.
      DRb.stop_service

      services.start_server
      begin
        services.start_client
        begin
          yield(services)
        ensure
          DRb.stop_service
        end
      ensure
        services.stop_server
      end
    end
    private :make_drb_services

    def test_server_load_limit
      make_drb_services(server_config: { load_limit: 256 }) {|services|
        services.call_service(:put, ' ' * 64)
        error = assert_raise(DRb::DRbConnError) { services.call_service(:put, ' ' * 1024) }
        assert_match(/too large packet/, error.message)
        services.call_service(:get, 64)
        services.call_service(:get, 1024)
      }
    end

    def test_client_load_limit
      make_drb_services(client_config: { load_limit: 256 }) {|services|
        services.call_service(:put, ' ' * 64)
        services.call_service(:put, ' ' * 1024)
        services.call_service(:get, 64)
        error = assert_raise(DRb::DRbConnError) { services.call_service(:get, 1024) }
        assert_match(/too large packet/, error.message)
      }
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
        assert_equal(0,   @services[:stateless].fib(0))
        assert_equal(1,   @services[:stateless].fib(1))
        assert_equal(1,   @services[:stateless].fib(2))
        assert_equal(2,   @services[:stateless].fib(3))
        assert_equal(3,   @services[:stateless].fib(4))
        assert_equal(5,   @services[:stateless].fib(5))
        assert_equal(8,   @services[:stateless].fib(6))
        assert_equal(13,  @services[:stateless].fib(7))
        assert_equal(21,  @services[:stateless].fib(8))
        assert_equal(34,  @services[:stateless].fib(9))
        assert_equal(55,  @services[:stateless].fib(10))
        assert_equal(89,  @services[:stateless].fib(11))
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
        assert_equal(0,   @services[:stateless].fib(0))
        assert_equal(1,   @services[:stateless].fib(1))
        assert_equal(1,   @services[:stateless].fib(2))
        assert_equal(2,   @services[:stateless].fib(3))
        assert_equal(3,   @services[:stateless].fib(4))
        assert_equal(5,   @services[:stateless].fib(5))
        assert_equal(8,   @services[:stateless].fib(6))
        assert_equal(13,  @services[:stateless].fib(7))
        assert_equal(21,  @services[:stateless].fib(8))
        assert_equal(34,  @services[:stateless].fib(9))
        assert_equal(55,  @services[:stateless].fib(10))
        assert_equal(89,  @services[:stateless].fib(11))
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
        assert_equal(0,   @services[:stateless, 'alice'].fib(0))
        assert_equal(1,   @services[:stateless, 'alice'].fib(1))
        assert_equal(1,   @services[:stateless, 'alice'].fib(2))
        assert_equal(2,   @services[:stateless, 'alice'].fib(3))
        assert_equal(3,   @services[:stateless, 'alice'].fib(4))
        assert_equal(5,   @services[:stateless, 'alice'].fib(5))
        assert_equal(8,   @services[:stateless, 'alice'].fib(6))
        assert_equal(13,  @services[:stateless, 'alice'].fib(7))
        assert_equal(21,  @services[:stateless, 'alice'].fib(8))
        assert_equal(34,  @services[:stateless, 'alice'].fib(9))
        assert_equal(55,  @services[:stateless, 'alice'].fib(10))
        assert_equal(89,  @services[:stateless, 'alice'].fib(11))
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

    def test_procedure_any_process_service
      @services.add_any_process_service(:fib, proc{|n| Fib.fib(n) })
      @services.start_server
      begin
        @services.start_client
        assert_equal(0,   @services[:fib, 0])
        assert_equal(1,   @services[:fib, 1])
        assert_equal(1,   @services[:fib, 2])
        assert_equal(2,   @services[:fib, 3])
        assert_equal(3,   @services[:fib, 4])
        assert_equal(5,   @services[:fib, 5])
        assert_equal(8,   @services[:fib, 6])
        assert_equal(13,  @services[:fib, 7])
        assert_equal(21,  @services[:fib, 8])
        assert_equal(34,  @services[:fib, 9])
        assert_equal(55,  @services[:fib, 10])
        assert_equal(89,  @services[:fib, 11])
        assert_equal(144, @services[:fib, 12])
        assert_equal(233, @services[:fib, 13])
        assert_equal(377, @services[:fib, 14])
        assert_equal(610, @services[:fib, 15])
      ensure
        @services.stop_server
      end
    end

    def test_procedure_single_process_service
      @services.add_single_process_service(:succ!, Count.new.method(:succ!))
      @services.start_server
      begin
        @services.start_client

        assert_equal(1, @services[:succ!, 'alice'])
        assert_equal(2, @services[:succ!, 'alice'])
        assert_equal(3, @services[:succ!, 'alice'])

        assert_equal(1, @services[:succ!, 'bob'])
        assert_equal(2, @services[:succ!, 'bob'])

        assert_equal(4, @services[:succ!, 'alice'])
        assert_equal(5, @services[:succ!, 'alice'])
      ensure
        @services.stop_server
      end
    end

    def test_procedure_sticky_process_service
      @services.add_sticky_process_service(:succ!, Count.new.method(:succ!))
      @services.start_server
      begin
        @services.start_client

        assert_equal(1, @services[:succ!, 'alice'])
        assert_equal(2, @services[:succ!, 'alice'])
        assert_equal(3, @services[:succ!, 'alice'])

        assert_equal(1, @services[:succ!, 'bob'])
        assert_equal(2, @services[:succ!, 'bob'])

        assert_equal(4, @services[:succ!, 'alice'])
        assert_equal(5, @services[:succ!, 'alice'])
      ensure
        @services.stop_server
      end
    end

    def test_procedure_block_any_process_service
      @services.add_any_process_service(:repeat, Repeat.method(:repeat))
      @services.start_server
      begin
        @services.start_client
        count = 0
        @services[:repeat, 2] { count += 1 }
        @services[:repeat, 3] { count += 1 }
        assert_equal(5, count)
      ensure
        @services.stop_server
      end
    end

    def test_procedure_block_single_process_service
      @services.add_single_process_service(:succ!, Count.new.method(:succ!))
      @services.start_server
      begin
        @services.start_client
        calls = 0

        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(1, count)
        }
        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(2, count)
        }
        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(3, count)
        }

        @services[:succ!, 'bob'] {|count|
          calls += 1
          assert_equal(1, count)
        }
        @services[:succ!, 'bob'] {|count|
          calls += 1
          assert_equal(2, count)
        }

        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(4, count)
        }
        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(5, count)
        }

        assert_equal(7, calls)
      ensure
        @services.stop_server
      end
    end

    def test_procedure_block_sticky_process_service
      @services.add_sticky_process_service(:succ!, Count.new.method(:succ!))
      @services.start_server
      begin
        @services.start_client
        calls = 0

        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(1, count)
        }
        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(2, count)
        }
        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(3, count)
        }

        @services[:succ!, 'bob'] {|count|
          calls += 1
          assert_equal(1, count)
        }
        @services[:succ!, 'bob'] {|count|
          calls += 1
          assert_equal(2, count)
        }

        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(4, count)
        }
        @services[:succ!, 'alice'] {|count|
          calls += 1
          assert_equal(5, count)
        }

        assert_equal(7, calls)
      ensure
        @services.stop_server
      end
    end
  end

  class DRbServicesHookTest < Test::Unit::TestCase
    def setup
      @test_obj = %w[ TEST1 TEST2 TEST3 ]
      @services = Riser::DRbServices.new(1)
      @services.add_any_process_service(:test1, @test_obj[0])
      @services.add_single_process_service(:test2, @test_obj[1])
      @services.add_sticky_process_service(:test3, @test_obj[2])
      @recorder = CallRecorder.new('drb_services_hook_test')
    end

    def teardown
      @recorder.dispose
    end

    def test_hooks_one_service
      @services.at_fork(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('at_fork')
      }
      @services.preprocess(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('preprocess')
      }
      @services.postprocess(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('postprocess')
      }

      @services.start_server
      begin
        @services.start_client
        assert_equal([], @recorder.get_memory_records)
        assert_equal(%w[ at_fork preprocess ], @recorder.get_file_records)
      ensure
        @services.stop_server
      end

      assert_equal([], @recorder.get_memory_records)
      assert_equal(%w[ at_fork preprocess postprocess ], @recorder.get_file_records)
    end

    def test_hooks_many_services
      @services.at_fork(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('test1.at_fork')
      }
      @services.preprocess(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('test1.preprocess')
      }
      @services.postprocess(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('test1.postprocess')
      }

      @services.at_fork(:test2) {|test|
        assert_equal(@test_obj[1], test)
        @recorder.call('test2.at_fork')
      }
      @services.preprocess(:test2) {|test|
        assert_equal(@test_obj[1], test)
        @recorder.call('test2.preprocess')
      }
      @services.postprocess(:test2) {|test|
        assert_equal(@test_obj[1], test)
        @recorder.call('test2.postprocess')
      }

      @services.at_fork(:test3) {|test|
        assert_equal(@test_obj[2], test)
        @recorder.call('test3.at_fork')
      }
      @services.preprocess(:test3) {|test|
        assert_equal(@test_obj[2], test)
        @recorder.call('test3.preprocess')
      }
      @services.postprocess(:test3) {|test|
        assert_equal(@test_obj[2], test)
        @recorder.call('test3.postprocess')
      }

      @services.start_server
      begin
        @services.start_client
        assert_equal([], @recorder.get_memory_records)
        assert_equal(%w[
                       test1.at_fork
                       test2.at_fork
                       test3.at_fork
                       test1.preprocess
                       test2.preprocess
                       test3.preprocess
                     ], @recorder.get_file_records)
      ensure
        @services.stop_server
      end

      assert_equal([], @recorder.get_memory_records)
      assert_equal(%w[
                     test1.at_fork
                     test2.at_fork
                     test3.at_fork
                     test1.preprocess
                     test2.preprocess
                     test3.preprocess
                     test3.postprocess
                     test2.postprocess
                     test1.postprocess
                   ], @recorder.get_file_records)
    end

    def test_hooks_stop_at_fork
      @services.at_fork(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('test1.at_fork')
      }
      @services.preprocess(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('test1.preprocess')
      }
      @services.postprocess(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('test1.postprocess')
      }

      @services.at_fork(:test2) {|test|
        assert_equal(@test_obj[1], test)
        @recorder.call('test2.at_fork')
        exit
      }
      @services.preprocess(:test2) {|test|
        assert_equal(@test_obj[1], test)
        @recorder.call('test2.preprocess')
      }
      @services.postprocess(:test2) {|test|
        assert_equal(@test_obj[1], test)
        @recorder.call('test2.postprocess')
      }

      @services.at_fork(:test3) {|test|
        assert_equal(@test_obj[2], test)
        @recorder.call('test3.at_fork')
      }
      @services.preprocess(:test3) {|test|
        assert_equal(@test_obj[2], test)
        @recorder.call('test3.preprocess')
      }
      @services.postprocess(:test3) {|test|
        assert_equal(@test_obj[2], test)
        @recorder.call('test3.postprocess')
      }

      @services.start_server
      @services.stop_server

      assert_equal([], @recorder.get_memory_records)
      assert_equal(%w[
                     test1.at_fork
                     test2.at_fork
                   ], @recorder.get_file_records)
    end

    def test_hooks_stop_preprocess
      @services.at_fork(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('test1.at_fork')
      }
      @services.preprocess(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('test1.preprocess')
      }
      @services.postprocess(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('test1.postprocess')
      }

      @services.at_fork(:test2) {|test|
        assert_equal(@test_obj[1], test)
        @recorder.call('test2.at_fork')
      }
      @services.preprocess(:test2) {|test|
        assert_equal(@test_obj[1], test)
        @recorder.call('test2.preprocess')
        exit
      }
      @services.postprocess(:test2) {|test|
        assert_equal(@test_obj[1], test)
        @recorder.call('test2.postprocess')
      }

      @services.at_fork(:test3) {|test|
        assert_equal(@test_obj[2], test)
        @recorder.call('test3.at_fork')
      }
      @services.preprocess(:test3) {|test|
        assert_equal(@test_obj[2], test)
        @recorder.call('test3.preprocess')
      }
      @services.postprocess(:test3) {|test|
        assert_equal(@test_obj[2], test)
        @recorder.call('test3.postprocess')
      }

      @services.start_server
      @services.stop_server

      assert_equal([], @recorder.get_memory_records)
      assert_equal(%w[
                     test1.at_fork
                     test2.at_fork
                     test3.at_fork
                     test1.preprocess
                     test2.preprocess
                     test1.postprocess
                   ], @recorder.get_file_records)
    end

    def test_hooks_stop_postprocess
      @services.at_fork(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('test1.at_fork')
      }
      @services.preprocess(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('test1.preprocess')
      }
      @services.postprocess(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('test1.postprocess')
      }

      @services.at_fork(:test2) {|test|
        assert_equal(@test_obj[1], test)
        @recorder.call('test2.at_fork')
      }
      @services.preprocess(:test2) {|test|
        assert_equal(@test_obj[1], test)
        @recorder.call('test2.preprocess')
      }
      @services.postprocess(:test2) {|test|
        assert_equal(@test_obj[1], test)
        @recorder.call('test2.postprocess')
        exit
      }

      @services.at_fork(:test3) {|test|
        assert_equal(@test_obj[2], test)
        @recorder.call('test3.at_fork')
      }
      @services.preprocess(:test3) {|test|
        assert_equal(@test_obj[2], test)
        @recorder.call('test3.preprocess')
      }
      @services.postprocess(:test3) {|test|
        assert_equal(@test_obj[2], test)
        @recorder.call('test3.postprocess')
      }

      @services.start_server
      @services.stop_server

      assert_equal([], @recorder.get_memory_records)
      assert_equal(%w[
                     test1.at_fork
                     test2.at_fork
                     test3.at_fork
                     test1.preprocess
                     test2.preprocess
                     test3.preprocess
                     test3.postprocess
                     test2.postprocess
                     test1.postprocess
                   ], @recorder.get_file_records)
    end
  end

  class DRbServicesHookMultiProcessTest < Test::Unit::TestCase
    def setup
      @test_obj = 'TEST'
      @druby_process_num = 4
      @services = Riser::DRbServices.new(@druby_process_num)
      @services.add_any_process_service(:test, @test_obj)
      @recorder = CallRecorder.new('drb_services_hook_process_test')
    end

    def teardown
      @recorder.dispose
    end

    def test_hooks
      @services.at_fork(:test) {|test|
        assert_equal(@test_obj, test)
        @recorder.call('at_fork')
      }
      @services.preprocess(:test) {|test|
        assert_equal(@test_obj, test)
        @recorder.call('preprocess')
      }
      @services.postprocess(:test) {|test|
        assert_equal(@test_obj, test)
        @recorder.call('postprocess')
      }

      @services.start_server
      begin
        @services.start_client
        assert_equal([], @recorder.get_memory_records)
        assert_equal(@druby_process_num * 2, @recorder.get_file_records.length)
        assert_equal(@druby_process_num, @recorder.get_file_records.count('at_fork'))
        assert_equal(@druby_process_num, @recorder.get_file_records.count('preprocess'))
      ensure
        @services.stop_server
      end

      assert_equal([], @recorder.get_memory_records)
      assert_equal(@druby_process_num * 3, @recorder.get_file_records.length)
      assert_equal(@druby_process_num, @recorder.get_file_records.count('at_fork'))
      assert_equal(@druby_process_num, @recorder.get_file_records.count('preprocess'))
      assert_equal(@druby_process_num, @recorder.get_file_records.count('postprocess'))
    end
  end

  class LocalServicesHookTest < Test::Unit::TestCase
    def setup
      @thread_report_on_exception = Thread.report_on_exception
      Thread.report_on_exception = false

      @test_obj = %w[ TEST1 TEST2 TEST3 ]
      @services = Riser::DRbServices.new(0)
      @services.add_any_process_service(:test1, @test_obj[0])
      @services.add_single_process_service(:test2, @test_obj[1])
      @services.add_sticky_process_service(:test3, @test_obj[2])
      @recorder = CallRecorder.new('local_services_hook_test')
    end

    def teardown
      Thread.report_on_exception = @thread_report_on_exception
      @recorder.dispose
    end

    def test_hooks_one_service
      @services.at_fork(:test1) {|test|
        flunk
      }
      @services.preprocess(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('preprocess')
      }
      @services.postprocess(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('postprocess')
      }

      @services.start_server
      begin
        @services.start_client
        assert_equal(%w[ preprocess ], @recorder.get_memory_records)
        assert_equal(%w[ preprocess ], @recorder.get_file_records)
      ensure
        @services.stop_server
      end

      assert_equal(%w[ preprocess postprocess ], @recorder.get_memory_records)
      assert_equal(%w[ preprocess postprocess ], @recorder.get_file_records)
    end

    def test_hooks_many_services
      @services.at_fork(:test1) {|test|
        flunk
      }
      @services.preprocess(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('test1.preprocess')
      }
      @services.postprocess(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('test1.postprocess')
      }

      @services.at_fork(:test2) {|test|
        flunk
        @recorder.call('test2.at_fork')
      }
      @services.preprocess(:test2) {|test|
        assert_equal(@test_obj[1], test)
        @recorder.call('test2.preprocess')
      }
      @services.postprocess(:test2) {|test|
        assert_equal(@test_obj[1], test)
        @recorder.call('test2.postprocess')
      }

      @services.at_fork(:test3) {|test|
        flunk
        @recorder.call('test3.at_fork')
      }
      @services.preprocess(:test3) {|test|
        assert_equal(@test_obj[2], test)
        @recorder.call('test3.preprocess')
      }
      @services.postprocess(:test3) {|test|
        assert_equal(@test_obj[2], test)
        @recorder.call('test3.postprocess')
      }

      @services.start_server
      begin
        @services.start_client
        assert_equal(%w[
                       test1.preprocess
                       test2.preprocess
                       test3.preprocess
                     ], @recorder.get_memory_records)
        assert_equal(%w[
                       test1.preprocess
                       test2.preprocess
                       test3.preprocess
                     ], @recorder.get_file_records)
      ensure
        @services.stop_server
      end

      assert_equal(%w[
                     test1.preprocess
                     test2.preprocess
                     test3.preprocess
                     test3.postprocess
                     test2.postprocess
                     test1.postprocess
                   ], @recorder.get_memory_records)
      assert_equal(%w[
                     test1.preprocess
                     test2.preprocess
                     test3.preprocess
                     test3.postprocess
                     test2.postprocess
                     test1.postprocess
                   ], @recorder.get_file_records)
    end

    def test_hooks_error_preprocess
      @services.at_fork(:test1) {|test|
        flunk
      }
      @services.preprocess(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('test1.preprocess')
      }
      @services.postprocess(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('test1.postprocess')
      }

      @services.at_fork(:test2) {|test|
        flunk
        @recorder.call('test2.at_fork')
      }
      @services.preprocess(:test2) {|test|
        assert_equal(@test_obj[1], test)
        @recorder.call('test2.preprocess')
        raise 'abort'
      }
      @services.postprocess(:test2) {|test|
        assert_equal(@test_obj[1], test)
        @recorder.call('test2.postprocess')
      }

      @services.at_fork(:test3) {|test|
        flunk
        @recorder.call('test3.at_fork')
      }
      @services.preprocess(:test3) {|test|
        assert_equal(@test_obj[2], test)
        @recorder.call('test3.preprocess')
      }
      @services.postprocess(:test3) {|test|
        assert_equal(@test_obj[2], test)
        @recorder.call('test3.postprocess')
      }

      @services.start_server
      begin
        error = assert_raise(RuntimeError) {
          @services.start_client
        }
        assert_equal('abort', error.message)
      ensure
        @services.stop_server
      end

      assert_equal(%w[
                     test1.preprocess
                     test2.preprocess
                     test1.postprocess
                  ], @recorder.get_memory_records)
      assert_equal(%w[
                     test1.preprocess
                     test2.preprocess
                     test1.postprocess
                   ], @recorder.get_file_records)
    end

    def test_hooks_stop_postprocess
      @services.at_fork(:test1) {|test|
        flunk
      }
      @services.preprocess(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('test1.preprocess')
      }
      @services.postprocess(:test1) {|test|
        assert_equal(@test_obj[0], test)
        @recorder.call('test1.postprocess')
      }

      @services.at_fork(:test2) {|test|
        flunk
        @recorder.call('test2.at_fork')
      }
      @services.preprocess(:test2) {|test|
        assert_equal(@test_obj[1], test)
        @recorder.call('test2.preprocess')
      }
      @services.postprocess(:test2) {|test|
        assert_equal(@test_obj[1], test)
        @recorder.call('test2.postprocess')
        raise 'abort'
      }

      @services.at_fork(:test3) {|test|
        flunk
        @recorder.call('test3.at_fork')
      }
      @services.preprocess(:test3) {|test|
        assert_equal(@test_obj[2], test)
        @recorder.call('test3.preprocess')
      }
      @services.postprocess(:test3) {|test|
        assert_equal(@test_obj[2], test)
        @recorder.call('test3.postprocess')
      }

      @services.start_server
      begin
        @services.start_client
      ensure
        error = assert_raise(RuntimeError) { @services.stop_server }
        assert_equal('abort', error.message)
      end

      assert_equal(%w[
                     test1.preprocess
                     test2.preprocess
                     test3.preprocess
                     test3.postprocess
                     test2.postprocess
                     test1.postprocess
                   ], @recorder.get_memory_records)
      assert_equal(%w[
                     test1.preprocess
                     test2.preprocess
                     test3.preprocess
                     test3.postprocess
                     test2.postprocess
                     test1.postprocess
                   ], @recorder.get_file_records)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
