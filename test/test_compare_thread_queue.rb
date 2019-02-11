# -*- coding: utf-8 -*-

require 'pp' if $DEBUG
require 'riser'
require 'test/unit'

module Riser::Test
  class ThreadQueueTest < Test::Unit::TestCase
    class CyclicBarrier
      def initialize(num_parties)
        @num_parties = num_parties
        @count = 0
        @mutex = Thread::Mutex.new
        @cond = Thread::ConditionVariable.new
      end

      def self.next_count_limit(count, num_parties)
        ((count / num_parties) + 1) * num_parties
      end

      def wait
        @mutex.synchronize{
          count_limit = self.class.next_count_limit(@count, @num_parties)
          @count += 1
          while (@count < count_limit)
            @cond.wait(@mutex)
          end
          @cond.broadcast
        }
        nil
      end
    end

    def setup
      @dt = 0.001
      @thread_num = 8
      @thread_list = []
      @count_max = 1_000
    end

    def measure_elapsed_time(name)
      start_time = Time.now
      yield
      end_time = Time.now
      puts "[#{name}: #{end_time - start_time}s]" if $DEBUG
    end
    private :measure_elapsed_time

    def test_queue
      queue = Thread::Queue.new
      push_values = (1..@count_max).to_a
      barrier = CyclicBarrier.new(@thread_num + 1)

      @thread_num.times do
        t = { :pop_values => [] }
        t[:thread] = Thread.start(t[:pop_values]) {|pop_values|
          barrier.wait
          begin
            while (value = queue.pop)
              pop_values << value
            end
          ensure
            barrier.wait
          end
        }
        @thread_list << t
      end

      measure_elapsed_time 'queue' do
        barrier.wait
        begin
          while (value = push_values.shift)
            queue.push(value)
          end
          queue.close
        ensure
          barrier.wait
        end
      end

      for t in @thread_list
        t[:thread].join
      end

      push_values = (1..@count_max).to_a
      pop_values = @thread_list.map{|t| t[:pop_values] }.flatten
      assert_equal(push_values, pop_values.sort)
    end

    def test_sized_queue
      queue = Thread::SizedQueue.new(@thread_num * 10)
      push_values = (1..@count_max).to_a
      barrier = CyclicBarrier.new(@thread_num + 1)

      @thread_num.times do
        t = { :pop_values => [] }
        t[:thread] = Thread.start(t[:pop_values]) {|pop_values|
          barrier.wait
          begin
            while (value = queue.pop)
              pop_values << value
            end
          ensure
            barrier.wait
          end
        }
        @thread_list << t
      end

      measure_elapsed_time 'sized queue' do
        barrier.wait
        begin
          while (value = push_values.shift)
            queue.push(value)
          end
          queue.close
        ensure
          barrier.wait
        end
      end

      for t in @thread_list
        t[:thread].join
      end

      push_values = (1..@count_max).to_a
      pop_values = @thread_list.map{|t| t[:pop_values] }.flatten
      assert_equal(push_values, pop_values.sort)
    end

    def test_timeout_sized_queue
      queue = Riser::TimeoutSizedQueue.new(@thread_num * 10, name: 'perf_test')
      # queue.stat_start
      push_values = (1..@count_max).to_a
      barrier = CyclicBarrier.new(@thread_num + 1)

      @thread_num.times do
        t = { :pop_values => [] }
        t[:thread] = Thread.start(t[:pop_values]) {|pop_values|
          barrier.wait
          begin
            while (value = queue.pop)
              pop_values << value
            end
          ensure
            barrier.wait
          end
        }
        @thread_list << t
      end

      measure_elapsed_time 'timeout sized queue' do
        barrier.wait
        begin
          while (value = push_values.shift)
            begin
              is_success = queue.push(value, @dt)
            end until (is_success)
          end
          queue.close
        ensure
          barrier.wait
        end
      end

      if ($DEBUG) then
        if (stat = queue.stat_get) then
          pp stat
        end
      end

      for t in @thread_list
        t[:thread].join
      end

      push_values = (1..@count_max).to_a
      pop_values = @thread_list.map{|t| t[:pop_values] }.flatten
      assert_equal(push_values, pop_values.sort)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
