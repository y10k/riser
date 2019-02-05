# -*- coding: utf-8 -*-

require 'drb/drb'
require 'drb/ssl'
require 'drb/unix'
require 'forwardable'

module Riser
  DRbService = Struct.new(:front, :at_fork, :preprocess, :postprocess, :ref) # :nodoc:
  DRbService::NO_CALL = proc{|front| } # :nodoc:

  class DRbServiceFront
    def initialize
      @mutex = Thread::Mutex.new
      @services = {}
    end

    def ping
      yield
    end

    def add_service(name, front)
      @services[name] = DRbService.new(front, DRbService::NO_CALL, DRbService::NO_CALL, DRbService::NO_CALL)
      nil
    end

    def at_fork(name, &block)   # :yields: service_front
      @services[name].at_fork = block
      nil
    end

    def preprocess(name, &block) # :yields: service_front
      @services[name].preprocess = block
    end

    def postprocess(name, &block) # :yields: service_front
      @services[name].postprocess = block
      nil
    end

    def apply_at_fork
      @services.each_value do |service|
        service.at_fork.call(service.front)
      end

      nil
    end

    def apply_service_hooks_by_name(pos, name_list)
      if (pos < name_list.length) then
        name = name_list[pos]
        service = @services[name]
        service.preprocess.call(service.front)
        begin
          apply_service_hooks_by_name(pos + 1, name_list) {
            yield
          }
        ensure
          service.postprocess.call(service.front)
        end
      else
        yield
      end
    end
    private :apply_service_hooks_by_name

    def apply_service_hooks
      apply_service_hooks_by_name(0, @services.keys) {
        yield
      }
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

    def_delegators :@front, :add_service, :at_fork, :preprocess, :postprocess

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
          @front.apply_at_fork
          @front.apply_service_hooks{
            DRb.start_service(drb_process.uri, @front, drb_process.config)
            while (latch_read_io.gets) # wait
            end
          }
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

  DRbCall = Struct.new(:there, :service_ref)                             # :nodoc:
  DRbAnyProcessService    = Struct.new(:process_type, :callable)         # :nodoc:
  DRbSingleProcessService = Struct.new(:process_type, :callable, :index) # :nodoc:
  DRbStickyProcessService = Struct.new(:process_type, :callable)         # :nodoc:

  class DRbServiceCall
    def initialize
      @mutex = Thread::Mutex.new
      @druby_call_list = []
      @single_process_service_count = 0
      @services = {}
      @random = nil
    end

    def add_druby_call(uri)
      @druby_call_list << DRbCall.new(DRbObject.new_with_uri(uri), {})
      nil
    end

    def add_any_process_service(name, callable=false)
      @services[name] = DRbAnyProcessService.new(:any, callable)
      nil
    end

    def add_single_process_service(name, callable=false)
      @services[name] = DRbSingleProcessService.new(:single, callable, @single_process_service_count)
      @single_process_service_count += 1
      nil
    end

    def add_sticky_process_service(name, callable=false)
      @services[name] = DRbStickyProcessService.new(:sticky, callable)
      nil
    end

    def self.is_callable(type_or_object)
      case (type_or_object)
      when Class
        object_type = type_or_object
        object_type.method_defined? :call
      else
        object = type_or_object
        object.respond_to? :call
      end
    end

    def add_any_process_service_with_type(name, type_or_object)
      add_any_process_service(name, DRbServiceCall.is_callable(type_or_object))
      nil
    end

    def add_single_process_service_with_type(name, type_or_object)
      add_single_process_service(name, DRbServiceCall.is_callable(type_or_object))
      nil
    end

    def add_sticky_process_service_with_type(name, type_or_object)
      add_sticky_process_service(name, DRbServiceCall.is_callable(type_or_object))
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
          druby_call.there.ping{ 'pong' }
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

    def start(timeout_seconds=30, local_druby_uri=Riser::TemporaryPath.make_drbunix_uri, config={ UNIXFileMode: 0600 })
      @random = Random.new
      unless (DRb.primary_server) then
        DRb.start_service(local_druby_uri, nil, config)
      end
      druby_ping(timeout_seconds)

      nil
    end

    def get_druby_service(name, index)
      druby_call = @druby_call_list[index]
      @mutex.synchronize{
        druby_call.service_ref[name] ||= druby_call.there.get_service(name)
      }
    end
    private :get_druby_service

    def get_any_process_service(name)
      get_druby_service(name, @mutex.synchronize{ @random.rand(@druby_call_list.length) })
    end
    private :get_any_process_service

    def get_single_process_service(name)
      get_druby_service(name, @services[name].index % @druby_call_list.length)
    end
    private :get_single_process_service

    def get_sticky_process_service(name, stickiness_key)
      get_druby_service(name, stickiness_key.hash % @druby_call_list.length)
    end
    private :get_sticky_process_service

    def get_service(name, *optional)
      if (@services.key? name) then
        case (@services[name].process_type)
        when :any
          get_any_process_service(name, *optional)
        when :single
          get_single_process_service(name, *optional)
        when :sticky
          get_sticky_process_service(name, *optional)
        else
          raise "internal error: (service_name,process_type)=(#{name},#{@services[name].process_type})"
        end
      else
        raise KeyError, "not found a service: #{name}"
      end
    end

    def call_any_process_service(name, *optional, &block)
      get_any_process_service(name).call(*optional, &block)
    end
    private :call_any_process_service

    def call_single_process_service(name, *optional, &block)
      get_single_process_service(name).call(*optional, &block)
    end
    private :call_single_process_service

    def call_sticky_process_service(name, stickiness_key, *optional, &block)
      get_sticky_process_service(name, stickiness_key).call(stickiness_key, *optional, &block)
    end
    private :call_sticky_process_service

    def call_service(name, *optional, &block)
      if (@services.key? name) then
        case (@services[name].process_type)
        when :any
          call_any_process_service(name, *optional, &block)
        when :single
          call_single_process_service(name, *optional, &block)
        when :sticky
          call_sticky_process_service(name, *optional, &block)
        else
          raise "internal error: (service_name,process_type)=(#{name},#{@services[name].process_type})"
        end
      else
        raise KeyError, "not found a service: #{name}"
      end
    end

    def [](name, *optional, &block)
      if (@services.key? name) then
        if (@services[name].callable) then
          call_service(name, *optional, &block)
        else
          get_service(name, *optional)
        end
      else
        raise KeyError, "not found a service: #{name}"
      end
    end
  end

  LocalService = Struct.new(:front, :preprocess, :postprocess, :process_type, :callable) # :nodoc:

  class LocalServiceServerClient
    def initialize
      @services = {}
      @hook_thread = nil
      @mutex = Thread::Mutex.new
      @state = nil
      @state_cond = Thread::ConditionVariable.new
      @stop = false
      @stop_cond = Thread::ConditionVariable.new
    end

    def add_service(name, front)
      @services[name] = LocalService.new(front, DRbService::NO_CALL, DRbService::NO_CALL)
      nil
    end

    def preprocess(name, &block) # :yields: service_front
      @services[name].preprocess = block
      nil
    end

    def postprocess(name, &block) # :yields: service_front
      @services[name].postprocess = block
      nil
    end

    def apply_service_hooks_by_name(pos, name_list)
      if (pos < name_list.length) then
        name = name_list[pos]
        service = @services[name]
        service.preprocess.call(service.front)
        begin
          apply_service_hooks_by_name(pos + 1, name_list) {
            yield
          }
        ensure
          service.postprocess.call(service.front)
        end
      else
        yield
      end
    end
    private :apply_service_hooks_by_name

    def apply_service_hooks
      apply_service_hooks_by_name(0, @services.keys) {
        yield
      }
    end
    private :apply_service_hooks

    def add_any_process_service(name, callable=false)
      @services[name].process_type = :any
      @services[name].callable = callable
      nil
    end

    def add_single_process_service(name, callable=false)
      @services[name].process_type = :single
      @services[name].callable = callable
      nil
    end

    def add_sticky_process_service(name, callable=false)
      @services[name].process_type = :sticky
      @services[name].callable = callable
      nil
    end

    def add_any_process_service_with_type(name, type_or_object)
      add_any_process_service(name, DRbServiceCall.is_callable(type_or_object))
      nil
    end

    def add_single_process_service_with_type(name, type_or_object)
      add_single_process_service(name, DRbServiceCall.is_callable(type_or_object))
      nil
    end

    def add_sticky_process_service_with_type(name, type_or_object)
      add_sticky_process_service(name, DRbServiceCall.is_callable(type_or_object))
      nil
    end

    def get_any_process_service(name)
      @services[name].front
    end
    private :get_any_process_service

    def get_single_process_service(name)
      @services[name].front
    end
    private :get_single_process_service

    def get_sticky_process_service(name, stickiness_key)
      @services[name].front
    end
    private :get_sticky_process_service

    def get_service(name, *optional)
      if (@services.key? name) then
        case (@services[name].process_type)
        when :any
          get_any_process_service(name, *optional)
        when :single
          get_single_process_service(name, *optional)
        when :sticky
          get_sticky_process_service(name, *optional)
        else
          raise "internal error: (service_name,process_type)=(#{name},#{@services[name].process_type})"
        end
      else
        raise KeyError, "not found a service: #{name}"
      end
    end

    def call_any_process_service(name, *optional, &block)
      get_any_process_service(name).call(*optional, &block)
    end
    private :call_any_process_service

    def call_single_process_service(name, *optional, &block)
      get_single_process_service(name).call(*optional, &block)
    end
    private :call_single_process_service

    def call_sticky_process_service(name, stickiness_key, *optional, &block)
      get_sticky_process_service(name, stickiness_key).call(stickiness_key, *optional, &block)
    end
    private :call_sticky_process_service

    def call_service(name, *optional, &block)
      if (@services.key? name) then
        case (@services[name].process_type)
        when :any
          call_any_process_service(name, *optional, &block)
        when :single
          call_single_process_service(name, *optional, &block)
        when :sticky
          call_sticky_process_service(name, *optional, &block)
        else
          raise "internal error: (service_name,process_type)=(#{name},#{@services[name].process_type})"
        end
      else
        raise KeyError, "not found a service: #{name}"
      end
    end

    def [](name, *optional, &block)
      if (@services.key? name) then
        if (@services[name].callable) then
          call_service(name, *optional, &block)
        else
          get_service(name, *optional)
        end
      else
        raise KeyError, "not found a service: #{name}"
      end
    end

    def start_server
      @hook_thread = Thread.new{
        begin
          apply_service_hooks{
            @mutex.synchronize{
              @state = :do
              @state_cond.signal
            }
            @mutex.synchronize{
              until (@stop)
                @stop_cond.wait(@mutex)
              end
            }
          }
        ensure
          @mutex.synchronize{
            @state = :done
            @state_cond.signal
          }
        end
      }

      nil
    end

    def start_client
      @mutex.synchronize{
        while (@state.nil?)
          @state_cond.wait(@mutex)
        end
      }

      # If the `do' state is skipped, propagate the error because an
      # error occurred.
      if (@mutex.synchronize{ @state } == :done) then
        @hook_thread.join
      end

      nil
    end

    def stop_server
      if (@mutex.synchronize{ @state } == :do) then
        @mutex.synchronize{
          @stop = true
          @stop_cond.signal
        }
        @hook_thread.join
      end

      nil
    end

    def get_server
      LocalServiceServer.new(self)
    end

    def get_client
      LocalServiceCall.new(self)
    end

    def self.make_pair
      server_client = new
      return server_client.get_server, server_client.get_client
    end
  end

  class LocalServiceServer
    extend Forwardable

    def initialize(services)
      @services = services
    end

    def at_fork(name)           # dummy
    end

    def detach                  # dummy
    end

    def_delegators :@services, :add_service, :preprocess, :postprocess
    def_delegator :@services, :start_server, :start
    def_delegator :@services, :stop_server, :stop
  end

  class LocalServiceCall
    extend Forwardable

    def initialize(services)
      @services = services
    end

    def_delegators :@services, :add_any_process_service, :add_single_process_service, :add_sticky_process_service
    def_delegators :@services, :add_any_process_service_with_type, :add_single_process_service_with_type, :add_sticky_process_service_with_type
    def_delegator :@services, :start_client, :start
    def_delegators :@services, :get_service, :call_service, :[]
  end

  class DRbServices
    extend Forwardable

    def initialize(druby_process_num=0)
      if (druby_process_num > 0) then
        @server = DRbServiceServer.new
        @call = DRbServiceCall.new
        druby_process_num.times do
          drb_uri = Riser::TemporaryPath.make_drbunix_uri
          @server.add_druby_process(drb_uri, UNIXFileMode: 0600)
          @call.add_druby_call(drb_uri)
        end
      else
        @server, @call = LocalServiceServerClient.make_pair
      end
    end

    def add_any_process_service(name, front)
      @server.add_service(name, front)
      @call.add_any_process_service_with_type(name, front)
      nil
    end

    def add_single_process_service(name, front)
      @server.add_service(name, front)
      @call.add_single_process_service_with_type(name, front)
      nil
    end

    def add_sticky_process_service(name, front)
      @server.add_service(name, front)
      @call.add_sticky_process_service_with_type(name, front)
      nil
    end

    def_delegators :@server, :at_fork, :preprocess, :postprocess
    def_delegator :@server, :start, :start_server
    def_delegator :@server, :detach, :detach_server # for forked child process
    def_delegator :@server, :stop, :stop_server

    def_delegator :@call, :start, :start_client
    def_delegators :@call, :get_service, :call_service, :[]
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
