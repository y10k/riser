# -*- coding: utf-8 -*-

require 'logger'
require 'riser'
require 'stringio'
require 'test/unit'

module Riser::Test
  class TestStream < Test::Unit::TestCase
    def test_to_io
      stream = Riser::Stream.new(STDOUT)
      stream = Riser::Stream.new(stream) # nested stream
      stream = Riser::Stream.new(stream) # nested-nested stream
      assert_equal(STDOUT, stream.to_io)
    end

    def make_string_stream(string="")
      @io = StringIO.new(string)
      @stream = Riser::Stream.new(@io)
      @stream = Riser::Stream.new(@stream) # nested stream
      @stream = Riser::Stream.new(@stream) # nested-nested stream
      nil
    end
    private :make_string_stream

    def test_gets
      make_string_stream("foo\nbar")
      assert_equal("foo\n", @stream.gets)
      assert_equal("bar", @stream.gets)
      assert_nil(@stream.gets)
    end

    def test_read
      make_string_stream('1234567')
      assert_equal('12345', @stream.read(5))
      assert_equal('67', @stream.read(5))
      assert_nil(@stream.read(5))
    end

    def test_write
      make_string_stream
      @stream.write('Hello ')
      assert_equal('Hello ', @io.string)
      @stream.write('world.')
      assert_equal('Hello world.', @io.string)
    end

    def test_append
      make_string_stream
      @stream << 'Hello' << ' ' << 'world' << '.'
      assert_equal('Hello world.', @io.string)
    end

    def test_flush
      make_string_stream
      @stream.flush
    end

    def test_close
      make_string_stream
      @stream.close
      assert_raise(IOError) { @io.gets }
      assert_raise(IOError) { @io.write('foo') }
    end
  end

  class WriteBufferStreamTest < Test::Unit::TestCase
    def setup
      @io = StringIO.new
      @stream = Riser::WriteBufferStream.new(Riser::Stream.new(@io), 8) # nested stream for restricted I/O check
    end

    def test_write
      @stream.write('12345')
      assert_equal('', @io.string)
      @stream.write('678')
      assert_equal('12345678', @io.string)
      @stream.write('12345678')
      assert_equal('12345678' * 2, @io.string)
    end

    def test_append
      @stream << '123' << '45'
      assert_equal('', @io.string)
      @stream << '678'
      assert_equal('12345678', @io.string)
      @stream << '12345678'
      assert_equal('12345678' * 2, @io.string)
    end

    def test_flush
      @stream.write('12345')
      assert_equal('', @io.string)
      @stream.flush
      assert_equal('12345', @io.string)
      @stream.write('12345678')
      assert_equal('12345' + '12345678', @io.string)
    end

    def test_close
      @stream.write('12345')
      assert_equal('', @io.string)
      @stream.close
      assert_equal('12345', @io.string)
      assert_raise(IOError) { @io.gets }
      assert_raise(IOError) { @io.write('foo') }
    end
  end

  class LoggingStreamTest < Test::Unit::TestCase
    def make_string_stream(string="")
      @io = StringIO.new(string)
      @log = StringIO.new
      @stream = Riser::LoggingStream.new(Riser::Stream.new(@io), Logger.new(@log)) # nested stream for restricted I/O check
      nil
    end
    private :make_string_stream

    def test_gets
      make_string_stream("foo\nbar")

      assert_equal("foo\n", @stream.gets)
      assert_match(/r "foo\\n"/, @log.string)
      assert_not_match(/r "bar"/, @log.string)
      assert_not_match(/r nil/, @log.string)

      assert_equal("bar", @stream.gets)
      assert_match(/r "foo\\n"/, @log.string)
      assert_match(/r "bar"/, @log.string)
      assert_not_match(/r nil/, @log.string)

      assert_nil(@stream.gets)
      assert_match(/r "foo\\n"/, @log.string)
      assert_match(/r "bar"/, @log.string)
      assert_match(/r nil/, @log.string)
    end

    def test_read
      make_string_stream('1234567')

      assert_equal('12345', @stream.read(5))
      assert_match(/r "12345"/, @log.string)
      assert_not_match(/r "67"/, @log.string)
      assert_not_match(/r nil/, @log.string)

      assert_equal('67', @stream.read(5))
      assert_match(/r "12345"/, @log.string)
      assert_match(/r "67"/, @log.string)
      assert_not_match(/r nil/, @log.string)

      assert_nil(@stream.read(5))
      assert_match(/r "12345"/, @log.string)
      assert_match(/r "67"/, @log.string)
      assert_match(/r nil/, @log.string)
    end

    def test_write
      make_string_stream

      @stream.write('foo')
      assert_match(/w "foo"/, @log.string)
      assert_not_match(/w "bar"/, @log.string)

      @stream.write('bar')
      assert_match(/w "foo"/, @log.string)
      assert_match(/w "bar"/, @log.string)
    end

    def test_append
      make_string_stream

      @stream << 'foo' << 'bar'
      assert_match(/w "foo"/, @log.string)
      assert_match(/w "bar"/, @log.string)
      assert_not_match(/w "baz"/, @log.string)

      @stream << 'baz'
      assert_match(/w "foo"/, @log.string)
      assert_match(/w "bar"/, @log.string)
      assert_match(/w "baz"/, @log.string)
    end

    def test_close
      make_string_stream

      @stream.close
      assert_match(/close/, @log.string)
      assert_raise(IOError) { @io.gets }
      assert_raise(IOError) { @io.write('foo') }
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
