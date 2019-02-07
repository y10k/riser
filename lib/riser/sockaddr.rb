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
          if (uri.host && uri.port) then
            return TCPSocketAddress.new(unsquare.call(uri.host), uri.port)
          end
        when /\A unix:/x
          uri = URI(config)
          if (uri.path && ! uri.path.empty?) then
            return UNIXSocketAddress.new(uri.path)
          end
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
            host    = config[:host]    || config['host']
            port    = config[:port]    || config['port']
            backlog = config[:backlog] || config['backlog']
            if ((host && (host.is_a? String) && ! host.empty?) &&
                (port && (port.is_a? Integer)) &&
                (backlog.nil? || (backlog.is_a? Integer)))
            then
              return TCPSocketAddress.new(unsquare.call(host), port, backlog)
            end
          when 'unix'
            path    = config[:path]    || config['path']
            backlog = config[:backlog] || config['backlog']
            mode    = config[:mode]    || config['mode']
            owner   = config[:owner]   || config['owner']
            group   = config[:group]   || config['group']
            if ((path && (path.is_a? String) && ! path.empty?) &&
                (backlog.nil? || (backlog.is_a? Integer)) &&
                (mode.nil? || (mode.is_a? Integer)) &&
                (owner.nil? || (owner.is_a? Integer) || ((owner.is_a? String) && ! owner.empty?)) &&
                (group.nil? || (group.is_a? Integer) || ((group.is_a? String) && ! group.empty?)))
            then
              return UNIXSocketAddress.new(path, backlog, mode, owner, group)
            end
          end
        end
      end

      return
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
