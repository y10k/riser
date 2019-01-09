# -*- coding: utf-8 -*-

require 'pp' if $DEBUG
require 'riser'
require 'test/unit'

module Riser::Test
  class TimeoutSizedQueueTest < Test::Unit::TestCase
    def setup
      @dt = 0.001
      @queue = Riser::TimeoutSizedQueue.new(3)
      @thread_num = 8
      @thread_list = []
      @count_max = 1000
    end

    def test_close
      assert_equal(false, @queue.closed?)
      @queue.close
      assert_equal(true, @queue.closed?)
      assert_nil(@queue.pop)
      assert_raise(RuntimeError) { @queue.push(:foo, @dt) }
    end

    def test_at_end_of_queue_with_data
      assert_equal(false, @queue.at_end_of_queue?)
      assert_not_nil(@queue.push(:foo, @dt))
      assert_equal(false, @queue.at_end_of_queue?)
      @queue.close
      assert_equal(false, @queue.at_end_of_queue?)
      @queue.pop
      assert_equal(true, @queue.at_end_of_queue?)
    end

    def test_at_end_of_queue_without_data
      assert_equal(false, @queue.at_end_of_queue?)
      @queue.close
      assert_equal(true, @queue.at_end_of_queue?)
    end

    def test_push_pop
      assert_equal(0, @queue.size)
      assert_equal(true, @queue.empty?)

      assert_not_nil(@queue.push(1, @dt))
      assert_equal(1, @queue.size)
      assert_equal(false, @queue.empty?)

      assert_not_nil(@queue.push(2, @dt))
      assert_equal(2, @queue.size)
      assert_equal(false, @queue.empty?)

      assert_not_nil(@queue.push(3, @dt))
      assert_equal(3, @queue.size)
      assert_equal(false, @queue.empty?)

      assert_nil(@queue.push(4, @dt))
      assert_equal(3, @queue.size)
      assert_equal(false, @queue.empty?)

      assert_equal(1, @queue.pop)
      assert_equal(2, @queue.size)
      assert_equal(false, @queue.empty?)

      assert_equal(2, @queue.pop)
      assert_equal(1, @queue.size)
      assert_equal(false, @queue.empty?)

      @queue.close
      assert_equal(1, @queue.size)
      assert_equal(false, @queue.empty?)

      assert_equal(3, @queue.pop)
      assert_equal(0, @queue.size)
      assert_equal(true, @queue.empty?)

      assert_nil(@queue.pop)
    end

    def test_push_pop_multithread
      @thread_num.times{
        t = { :pop_values => [] }
        t[:thread] = Thread.new{
          while (value = @queue.pop)
            t[:pop_values] << value
          end
        }
        @thread_list << t
      }

      push_values = (1..@count_max).to_a
      while (value = push_values.shift)
        begin
          is_success = @queue.push(value, @dt)
        end until (is_success)
      end
      @queue.close

      for t in @thread_list
        t[:thread].join
      end
      pp @thread_list if $DEBUG

      @thread_list.each_with_index do |t, i|
        assert(t[:pop_values].length > 0, "@thread_list[#{i}][:pop_values].length")
        (t[:pop_values].length - 1).times do |j|
          assert(t[:pop_values][j] < t[:pop_values][j + 1], "@thread_list[#{i}][#{:pop_values}][#{j}]")
        end
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
