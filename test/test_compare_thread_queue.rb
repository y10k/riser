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
        @mutex = Mutex.new
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
      queue = Queue.new
      push_values = (1..@count_max).to_a
      barrier = CyclicBarrier.new(@thread_num + 1)

      @thread_num.times{
        t = { :pop_values => [] }
        t[:thread] = Thread.new{
          barrier.wait
          begin
            while (value = queue.pop)
              t[:pop_values] << value
            end
          ensure
            barrier.wait
          end
        }
        @thread_list << t
      }

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
      queue = SizedQueue.new(@thread_num * 10)
      push_values = (1..@count_max).to_a
      barrier = CyclicBarrier.new(@thread_num + 1)

      @thread_num.times{
        t = { :pop_values => [] }
        t[:thread] = Thread.new{
          barrier.wait
          begin
            while (value = queue.pop)
              t[:pop_values] << value
            end
          ensure
            barrier.wait
          end
        }
        @thread_list << t
      }

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

    def test_pull_buffer
      buf = Riser::PullBuffer.new
      push_values = (1..@count_max).to_a
      barrier = CyclicBarrier.new(@thread_num + 1)

      @thread_num.times{
        t = { :pull_values => [] }
        t[:thread] = Thread.new{
          barrier.wait
          begin
            until (buf.at_end_of_buffer?)
              if (value = buf.pull(@dt)) then
                t[:pull_values] << value
              end
            end
          ensure
            barrier.wait
          end
        }
        @thread_list << t
      }

      measure_elapsed_time 'pull buffer' do
        barrier.wait
        begin
          until (push_values.empty?)
            if (buf.push_ready?(@dt)) then
              buf.push(push_values.shift)
            end
          end
          buf.close
        ensure
          barrier.wait
        end
      end

      for t in @thread_list
        t[:thread].join
      end

      push_values = (1..@count_max).to_a
      pull_values = @thread_list.map{|t| t[:pull_values] }.flatten
      assert_equal(push_values, pull_values.sort)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
