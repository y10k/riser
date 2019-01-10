# -*- coding: utf-8 -*-

module Riser
  # restricted I/O framework
  class Stream
    def initialize(io)
      @io = io
    end

    def to_io
      @io.to_io
    end

    def gets
      @io.gets
    end

    def read(size)
      @io.read(size)
    end

    def write(message)
      @io.write(message)
    end

    def <<(message)
      write(message)
      self
    end

    def flush
      @io.flush
      self
    end

    def close
      flush
      @io.close
      nil
    end
  end

  class WriteBufferStream < Stream
    def initialize(io, buffer_limit=1024*16)
      super(io)
      @buffer_limit = buffer_limit
      @buffer_string = ''.b
    end

    def write_and_flush
      write_bytes = @io.write(@buffer_string)
      while (write_bytes < @buffer_string.bytesize)
        remaining_byte_range = write_bytes..-1
        write_bytes += @io.write(@buffer_string.byteslice(remaining_byte_range))
      end
      @buffer_string.clear
      @io.flush
      write_bytes
    end
    private :write_and_flush

    def write(message)
      @buffer_string << message.b
      write_and_flush if (@buffer_string.bytesize >= @buffer_limit)
    end

    def flush
      write_and_flush unless @buffer_string.empty?
      self
    end
  end

  class LoggingStream < Stream
    def initialize(io, logger)
      super(io)
      @logger = logger
    end

    def gets
      line = super
      @logger.info("r #{line.inspect}")
      line
    end

    def read(size)
      data = super
      @logger.info("r #{data.inspect}")
      data
    end

    def write(message)
      @logger.info("w #{message.inspect}")
      super
    end

    def close
      @logger.info('close')
      super
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End: