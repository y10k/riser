# -*- coding: utf-8 -*-

require 'pp' if $DEBUG
require 'riser'
require 'test/unit'

module Riser::Test
  class PullBufferTest < Test::Unit::TestCase
    def setup
      @dt = 0.001
      @buf = Riser::PullBuffer.new
      @thread_num = 8
      @thread_list = []
      @count_max = 1000
    end

    def test_close
      assert_equal(false, @buf.closed?)
      assert_nil(@buf.pull(@dt))
      assert_equal(false, @buf.push_ready?(@dt))

      @buf.close
      assert_equal(true, @buf.closed?)
      assert_nil(@buf.pull(@dt))
      assert_raise(RuntimeError) { @buf.push_ready?(@dt) }
      assert_raise(RuntimeError) { @buf.push(:foo) }
    end

    def test_at_end_of_buffer_with_data
      assert_equal(false, @buf.at_end_of_buffer?)
      @buf.push(:foo)
      assert_equal(false, @buf.at_end_of_buffer?)
      @buf.close
      assert_equal(false, @buf.at_end_of_buffer?)
      @buf.pull(@dt)
      assert_equal(true, @buf.at_end_of_buffer?)
    end

    def test_at_end_of_buffer_without_data
      assert_equal(false, @buf.at_end_of_buffer?)
      @buf.close
      assert_equal(true, @buf.at_end_of_buffer?)
    end

    def test_not_ready_to_push
      @buf.push(:foo)
      assert_raise(RuntimeError) { @buf.push(:bar) }
    end

    def test_pull_push
      start_time = Time.now

      @thread_num.times{
        t = { :pull_values => [] }
        t[:thread] = Thread.new{
          until (@buf.at_end_of_buffer?)
            if (value = @buf.pull(@dt)) then
              t[:pull_values] << value
            end
          end
        }
        @thread_list << t
      }

      push_values = (1..@count_max).to_a
      until (push_values.empty?)
        if (@buf.push_ready?(@dt)) then
          @buf.push(push_values.shift)
        end
      end
      @buf.close

      for t in @thread_list
        t[:thread].join
      end

      end_time = Time.now
      if ($DEBUG) then
        pp (end_time - start_time)
        pp @thread_list
      end

      @thread_list.each_with_index do |t, i|
        assert(t[:pull_values].length > 0, "@thread_list[#{i}][:pull_values].length")
        t[:pull_values].each_with_index do |value, j|
          assert(((1..@count_max).cover? value), "@thread_list[#{i}][:pull_values][#{j}]")
        end
        (t[:pull_values].length - 1).times do |j|
          assert(t[:pull_values][j] < t[:pull_values][j + 1], "@thread_list[#{i}][:pull_values][#{j}]")
        end
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
