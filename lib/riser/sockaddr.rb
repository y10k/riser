# -*- coding: utf-8 -*-

require 'socket'
require 'uri'

module Riser
  class SocketAddress
    def initialize(type, backlog=nil)
      @type = type
      @backlog = backlog
    end

    attr_reader :type
    attr_reader :backlog

    def to_address
      [ @type ]
    end

    def to_option
      option = {}
      option[:backlog] = @backlog if @backlog
      option
    end

    def ==(other)
      if (other.is_a? SocketAddress) then
        [ self.to_address, self.to_option ] == [ other.to_address, other.to_option ]
      else
        false
      end
    end

    def eql?(other)
      self == other
    end

    def hash
      [ to_address, to_option ].hash ^ self.class.hash
    end

    def self.parse(config)
      unsquare = proc{|s| s.sub(/\A \[/x, '').sub(/\] \z/x, '') }
      case (config)
      when String
        case (config)
        when /\A tcp:/x
          uri = URI(config)
          uri.host or raise ArgumentError, 'need for a tcp socket uri host.'
          uri.port or raise ArgumentError, 'need for a tcp socket uri port.'
          return TCPSocketAddress.new(unsquare.call(uri.host), uri.port)
        when /\A unix:/x
          uri = URI(config)
          uri.path or raise ArgumentError, 'need for a unix socket uri path.'
          uri.path.empty? and raise ArgumentError, 'empty unix socket uri path.'
          return UNIXSocketAddress.new(uri.path)
        when %r"\A [A-Za-z]+:/"x
          # unknown URI scheme
        when /\A (\S+):(\d+) \z/x
          host = $1
          port = $2.to_i
          return TCPSocketAddress.new(unsquare.call(host), port)
        end
      when Hash
        if (type = config[:type] || config['type']) then
          case (type.to_s)
          when 'tcp'
            host = config[:host] || config['host'] or raise ArgumentError, 'need for a tcp socket host.'
            (host.is_a? String) or raise TypeError, 'not a string tcp scoket host.'
            host.empty? and raise ArgumentError, 'empty tcp socket host.'

            port = config[:port] || config['port'] or raise ArgumentError, 'need for a tcp socket port.'
            (port.is_a? Integer) or raise TypeError, 'not a integer tcp socket port.'

            if (backlog = config[:backlog] || config['backlog']) then
              (backlog.is_a? Integer) or raise TypeError, 'not a integer tcp socket backlog.'
            end

            return TCPSocketAddress.new(unsquare.call(host), port, backlog)
          when 'unix'
            path = config[:path] || config['path'] or raise ArgumentError, 'need for a unix socket path.'
            (path.is_a? String) or raise TypeError, 'not a string unix socket path.'
            path.empty? and raise ArgumentError, 'empty unix socket path.'

            if (backlog = config[:backlog] || config['backlog']) then
              (backlog.is_a? Integer) or raise TypeError, 'not a integer unix socket backlog.'
            end

            if (mode = config[:mode] || config['mode']) then
              (mode.is_a? Integer) or raise TypeError, 'not a integer socket mode.'
            end

            if (owner = config[:owner] || config['owner']) then
              unless ((owner.is_a? Integer) || (owner.is_a? String)) then
                raise TypeError, 'unix socket owner is neither an integer nor a string.'
              end
              if (owner.is_a? String) then
                if (owner.empty?) then
                  raise ArgumentError, 'empty unix socket owner.'
                end
              end
            end

            if (group = config[:group] || config['group']) then
              unless ((group.is_a? Integer) || (group.is_a? String)) then
                raise TypeError, 'unix socket group is neither an integer nor a string.'
              end
              if (group.is_a? String) then
                if (group.empty?) then
                  raise ArgumentError, 'empty unix socket group.'
                end
              end
            end

            return UNIXSocketAddress.new(path, backlog, mode, owner, group)
          end
        end
      end

      raise ArgumentError, 'invalid socket address.'
    end
  end

  class TCPSocketAddress < SocketAddress
    def initialize(host, port, backlog=nil)
      super(:tcp, backlog)
      @host = host
      @port = port
    end

    attr_reader :host
    attr_reader :port

    def to_address
      super << @host <<  @port
    end

    def to_s
      if (@host.include? ':') then
        "tcp://[#{host}]:#{port}"
      else
        "tcp://#{host}:#{port}"
      end
    end

    def open_server
      TCPServer.new(@host, @port)
    end
  end

  class UNIXSocketAddress < SocketAddress
    def initialize(path, backlog=nil, mode=nil, owner=nil, group=nil)
      super(:unix, backlog)
      @path = path
      @mode = mode
      @owner = owner
      @group = group
    end

    attr_reader :path
    attr_reader :mode
    attr_reader :owner
    attr_reader :group

    def to_address
      super << @path
    end

    def to_option
      option = super
      option[:mode] = @mode if @mode
      option[:owner] = @owner if @owner
      option[:group] = @group if @group
      option
    end

    def to_s
      "unix:#{@path}"
    end

    def open_server
      UNIXServer.new(@path)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
