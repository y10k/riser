# -*- coding: utf-8 -*-

require 'drb/drb'
require 'drb/ssl'
require 'drb/unix'
require 'forwardable'
require 'securerandom'
require 'thread'
require 'tmpdir'

module Riser
  def make_unix_socket_path
    tmp_dir = Dir.tmpdir
    uuid = SecureRandom.uuid
    "#{tmp_dir}/riser_#{uuid}"
  end
  module_function :make_unix_socket_path

  def make_drbunix_uri
    "drbunix:#{make_unix_socket_path}.drb"
  end
  module_function :make_drbunix_uri

  DRbServicePair = Struct.new(:front, :ref) # :nodoc:

  class DRbServiceFront
    def initialize
      @mutex = Mutex.new
      @services = {}
    end

    def ping
      'pong'
    end

    def add_service(name, front)
      @services[name] = DRbServicePair.new(front)
      nil
    end

    def get_service(name)
      @mutex.synchronize{
        @services[name].ref ||= DRbObject.new(@services[name].front)
      }
    end
  end

  DRbProcess = Struct.new(:uri, :config, :latch_write_io, :pid) # :nodoc:

  class DRbServiceServer
    extend Forwardable

    def initialize
      @front = DRbServiceFront.new
      @druby_process_list = []
    end

    def_delegator :@front, :add_service

    def add_druby_process(uri, config={})
      @druby_process_list << DRbProcess.new(uri, config)
      nil
    end

    def start
      @druby_process_list.each_with_index do |drb_process, pos|
        latch_read_io, latch_write_io = IO.pipe
        pid = Process.fork{
          latch_write_io.close
          pos.times do |i|
            @druby_process_list[i].latch_write_io.close
          end
          DRb.start_service(drb_process.uri, @front, drb_process.config)
          while (latch_read_io.gets) # wait
          end
        }
        latch_read_io.close
        drb_process.latch_write_io = latch_write_io
        drb_process.pid = pid
      end

      nil
    end

    # for forked child process
    def detach
      for drb_process in @druby_process_list
        drb_process.latch_write_io.close
      end

      nil
    end

    def wait
      for drb_process in @druby_process_list
        Process.waitpid(drb_process.pid)
      end

      nil
    end

    def stop
      detach
      wait
    end
  end

  DRbCall = Struct.new(:there, :service_ref) # :nodoc:

  class DRbServiceCall
    def initialize
      @mutex = Mutex.new
      @service_names = {}
      @druby_call_list = []
      @random = nil
    end

    def add_any_process_service(name)
      @service_names[name] = :any
    end

    def add_single_process_service(name)
      @service_names[name] = :single
    end

    def add_sticky_process_service(name)
      @service_names[name] = :sticky
    end

    def add_druby_call(uri)
      @druby_call_list << DRbCall.new(DRbObject.new_with_uri(uri), {})
      nil
    end

    def druby_ping(timeout_seconds)
      t0 = Time.now
      if (timeout_seconds > 0.1) then
        dt = 0.1
      else
        dt = timeout_seconds * 0.1
      end

      for druby_call in @druby_call_list
        begin
          druby_call.there.ping
        rescue DRb::DRbConnError
          if (Time.now - t0 >= timeout_seconds) then
            raise
          else
            sleep(dt)
          end
          retry
        end
      end

      nil
    end

    def start(timeout_seconds=30, local_druby_uri=Riser.make_drbunix_uri, config={ UNIXFileMode: 0600 })
      @random = Random.new
      unless (DRb.primary_server) then
        DRb.start_service(local_druby_uri, nil, config)
      end
      druby_ping(timeout_seconds)

      nil
    end

    def get_druby_service(name, stickiness_key)
      i = stickiness_key.hash % @druby_call_list.length
      druby_call = @druby_call_list[i]
      @mutex.synchronize{
        druby_call.service_ref[name] ||= druby_call.there.get_service(name)
      }
    end
    private :get_druby_service

    def get_service(name)
      case (@service_names[name])
      when :any
        get_druby_service(name, @mutex.synchronize{ @random.rand })
      when :single
        get_druby_service(name, name)
      when :sticky
        raise ArgumentError, "a sticky process service needs for a stickiness key: #{name}"
      else
        raise KeyError, "not found a service: #{name}"
      end
    end

    def get_sticky_process_service(name, stickiness_key)
      case (@service_names[name])
      when :sticky
        get_druby_service(name, stickiness_key)
      when :any, :single
        raise ArgumentError, "not a sticky process service: #{name}"
      else
        raise KeyError, "not found a service: #{name}"
      end
    end

    def [](name, stickiness_key=nil)
      if (stickiness_key.nil?) then
        get_service(name)
      else
        get_sticky_process_service(name, stickiness_key)
      end
    end
  end

  class LocalServiceCall
    def initialize
      @services = {}
    end

    def add_service(name, front)
      @services[name] = front
      nil
    end

    def add_any_process_service(name) # dummy
    end

    def add_single_process_service(name) # dummy
    end

    def add_sticky_process_service(name) # dummy
    end

    def get_service(name)
      @services[name] or raise KeyError, "not found a service: #{name}"
    end

    def get_sticky_process_service(name, stickiness_key) # dummy
      get_service(name)
    end

    def [](name, stickiness_key=nil)
      get_service(name)
    end

    def start                   # dummy
    end

    def detach                  # dummy
    end

    def stop                    # dummy
    end
  end

  class DRbServices
    extend Forwardable

    def initialize(druby_process_num=0)
      if (druby_process_num > 0) then
        @server = DRbServiceServer.new
        @call = DRbServiceCall.new
        druby_process_num.times do
          drb_uri = Riser.make_drbunix_uri
          @server.add_druby_process(drb_uri, UNIXFileMode: 0600)
          @call.add_druby_call(drb_uri)
        end
      else
        @server = @call = LocalServiceCall.new
      end
    end

    def add_any_process_service(name, front)
      @server.add_service(name, front)
      @call.add_any_process_service(name)
      nil
    end

    def add_single_process_service(name, front)
      @server.add_service(name, front)
      @call.add_single_process_service(name)
      nil
    end

    def add_sticky_process_service(name, front)
      @server.add_service(name, front)
      @call.add_sticky_process_service(name)
      nil
    end

    def_delegator :@server, :start, :start_server
    def_delegator :@server, :detach, :detach_server # for forked child process
    def_delegator :@server, :stop, :stop_server

    def_delegator :@call, :start, :start_client
    def_delegators :@call, :get_service, :get_sticky_process_service, :[]
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
