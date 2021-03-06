# -*- coding: utf-8 -*-

require 'logger'
require 'pp'if $DEBUG
require 'riser'
require 'socket'
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

    data('default'        => [ "foo\n",     "foo\n", [],          {} ],
         'rs'             => [ "foo\r",     "foo\r", [ "\r" ],    {} ],
         'chomp'          => [ "foo\n",     'foo',   [],          { chomp: true } ],
         'rs_chomp'       => [ "foo\r",     'foo',   [ "\r" ],    { chomp: true } ],
         'limit'          => [ "foo_bar\n", 'foo_',  [ 4 ],       {} ],
         'rs_limit_chomp' => [ "foo_bar\r", 'foo_',  [ "\r", 4 ], { chomp: true } ])
    def test_gets_optional_arguments(data)
      input_data, expected_line, args, kw_args = data
      src, dst = UNIXSocket.socketpair
      begin
        begin
          src << input_data
          stream = Riser::Stream.new(dst)
          assert_equal(expected_line, stream.gets(*args, **kw_args))
        ensure
          src.close
        end
      ensure
        dst.close
      end
    end

    def test_read
      make_string_stream('1234567')
      assert_equal('12345', @stream.read(5))
      assert_equal('67', @stream.read(5))
      assert_nil(@stream.read(5))
    end

    def test_readpartial
      read_io, write_io = IO.pipe
      begin
        @stream = Riser::Stream.new(read_io)
        @stream = Riser::Stream.new(@stream) # nested stream
        @stream = Riser::Stream.new(@stream) # nested-nested stream

        write_io << 'foo'
        assert_equal('foo', @stream.readpartial(1024))

        write_io << 'bar'
        s = ''
        assert_equal('bar', @stream.readpartial(1024, s))
        assert_equal('bar', s)

        write_io.close
        assert_raise(EOFError) { @stream.readpartial(1024) }
      ensure
        read_io.close unless read_io.closed?
        write_io.close unless write_io.closed?
      end
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
      @logger = Logger.new(@log)
      @logger.level = Logger::DEBUG if $DEBUG
      @stream = Riser::LoggingStream.new(Riser::Stream.new(@io), @logger) # nested stream for restricted I/O check
      nil
    end
    private :make_string_stream

    def teardown
      if ($DEBUG) then
        puts @log.string
      end
    end

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

    def test_gets_optional_arguments
      make_string_stream("foo\rbar")

      assert_equal("foo\r", @stream.gets("\r"))
      assert_match(/r "foo\\r"/, @log.string)
      assert_not_match(/r "bar"/, @log.string)
      assert_not_match(/r nil/, @log.string)

      assert_equal("bar", @stream.gets("\r"))
      assert_match(/r "foo\\r"/, @log.string)
      assert_match(/r "bar"/, @log.string)
      assert_not_match(/r nil/, @log.string)

      assert_nil(@stream.gets("\r"))
      assert_match(/r "foo\\r"/, @log.string)
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

    def test_readpartial
      read_io, write_io = IO.pipe
      begin
        @log = StringIO.new
        @stream = Riser::LoggingStream.new(Riser::Stream.new(read_io), Logger.new(@log)) # nested stream for restricted I/O check

        write_io << 'foo'
        assert_equal('foo', @stream.readpartial(1024))
        assert_match(/r "foo"/, @log.string)
        assert_not_match(/r "bar"/, @log.string)

        write_io << 'bar'
        assert_equal('bar', @stream.readpartial(1024))
        assert_match(/r "foo"/, @log.string)
        assert_match(/r "bar"/, @log.string)
      ensure
        read_io.close unless read_io.closed?
        write_io.close unless write_io.closed?
      end
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

    def test_flush
      make_string_stream

      @stream.flush
      assert_match(/flush/, @log.string)
    end

    def test_close
      make_string_stream

      @stream.close
      assert_match(/close/, @log.string)
      assert_raise(IOError) { @io.gets }
      assert_raise(IOError) { @io.write('foo') }
    end
  end

  class LoggingStreamClassMethodTest < Test::Unit::TestCase
    data('STDOUT'     => STDOUT,
         'STDIN'      => STDIN,
         'STDERR'     => STDERR,
         'StringIO'   => StringIO.new,
         'tcp'        => StringIO.new.tap{|s| def s.remote_address; Addrinfo.tcp('localhost', 30000); end },
         'unix:empty' => StringIO.new.tap{|s| def s.remote_address; Addrinfo.unix(''); end },
         'unix:path'  => StringIO.new.tap{|s| def s.remote_address; Addrinfo.unix('/tmp/foo'); end })
    def test_make_tag(io)
      tag = Riser::LoggingStream.make_tag(io)
      pp tag if $DEBUG
      assert_instance_of(String, tag)
      assert(! tag.empty?)
      assert_equal(tag, Riser::LoggingStream.make_tag(io), 'if same object then same tag')
    end

    data('IO'       => [ STDIN, STDERR ],
         'StringIO' => [ StringIO.new, StringIO.new ],
         'hetero'   => [ STDIN, StringIO.new ])
    def test_make_tag_identified(data)
      io1, io2 = data
      tag1 = Riser::LoggingStream.make_tag(io1)
      tag2 = Riser::LoggingStream.make_tag(io2)
      assert(tag1 != tag2)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
