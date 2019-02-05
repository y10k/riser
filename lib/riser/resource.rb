# -*- coding: utf-8 -*-

require 'delegate'
require 'drb'
require 'forwardable'
require 'riser'
require 'set'

module Riser
  class Resource
    class Manager
      def initialize(create, destroy)
        @mutex = Thread::Mutex.new
        @create = create
        @destroy = destroy
        @ref_count = 0
        @ref_object = nil
        @ref_proxy = {}         # to keep proxy objects living in dRuby process
      end

      def ref_count
        @mutex.synchronize{ @ref_count }
      end

      def proxy_count
        @mutex.synchronize{ @ref_proxy.length }
      end

      def ref_object?
        @mutex.synchronize{ ! @ref_object.nil? }
      end

      def ref_object
        @mutex.synchronize{
          if (@ref_count < 0) then
            raise "internal error: negative reference count <#{@ref_count}>"
          end

          if (@ref_count == 0) then
            # if an exception occurs at `@create.call', the object should not be referenced.
            @ref_object = @create.call
          end
          @ref_count += 1
          @ref_object
        }
      end

      def unref_object
        @mutex.synchronize{
          unless (@ref_count > 0) then
            raise "internal error: unreferenced resource object <#{@ref_count}>"
          end

          @ref_count -= 1
          if (@ref_count == 0) then
            tmp_object = @ref_object
            @ref_object = nil
            # even if an exception occurs at `@destroy.call', the object should be unreferenced.
            @destroy.call(tmp_object)
          end
        }

        nil
      end

      def ref_proxy(proxy)
        @mutex.synchronize{
          if (@ref_proxy.key? proxy.__id__) then
            raise "internal error: duplicated proxy object <#{proxy.__id__}>"
          end
          @ref_proxy[proxy.__id__] = proxy
        }
      end

      def unref_proxy(proxy)
        @mutex.synchronize{
          @ref_proxy.delete(proxy.__id__) or raise "internal error: unreferenced proxy object <#{proxy.__id__}>"
        }
      end
    end

    module Delegatable
      def __getobj__
        if (@delegate_proxy_obj.nil?) then
          return yield if block_given?
          __raise__ ::ArgumentError, "not delegated"
        end
        @delegate_proxy_obj
      end

      def __setobj__(obj)
        __raise__ ::ArgumentError, "cannot delegate to self" if self.equal?(obj)
        @delegate_proxy_obj = obj
      end
      protected :__setobj__
    end

    module DelegateUnrefAlias
      def method_missing(name, *args, &block)
        if (@unref_alias_set.include? name.to_sym) then
          __unref__
        else
          super
        end
      end

      def respond_to_missing?(name, include_private)
        if (@unref_alias_set.include? name.to_sym) then
          true
        else
          super
        end
      end
    end

    class Proxy < Delegator
      include DRb::DRbUndumped
      include Delegatable
      include DelegateUnrefAlias

      def initialize(manager, unref_alias_set)
        @manager = manager
        @unref_alias_set = unref_alias_set
        # if an exception occurs at `@create.call', the proxy should not be referenced.
        super(@manager.ref_object)
        @manager.ref_proxy(self)
      end

      def __unref__
        delegated = true
        __getobj__{ delegated = false }

        if (delegated) then
          __setobj__(nil)
          @manager.unref_proxy(self)
          # even if an exception occurs at `@destroy.call', the proxy should be unreferenced.
          @manager.unref_object
        end

        nil
      end
    end

    class Builder
      def initialize
        @create = nil
        @destroy = nil
        @unref_alias_set = Set.new
      end

      def at_create(&block)     # :yields:
        @create = block
        nil
      end

      def at_destroy(&block)    # :yields: resource_object
        @destroy = block
        nil
      end

      def alias_unref(name)
        @unref_alias_set << name.to_sym
        nil
      end

      def call
        @create or raise 'not defined create block'
        @destroy or raise 'not defined destroy block'
        Resource.new(Manager.new(@create, @destroy), @unref_alias_set)
      end
    end

    def self.build
      build = Builder.new
      yield(build)
      build.call
    end

    extend Forwardable
    include DRb::DRbUndumped

    def initialize(manager, unref_alias_set)
      @manager = manager
      @unref_alias_set = unref_alias_set
    end

    def_delegators :@manager, :ref_count, :proxy_count, :ref_object?

    def call
      proxy = Proxy.new(@manager, @unref_alias_set)
      if (block_given?) then
        begin
          yield(proxy)
        ensure
          proxy.__unref__
        end
      else
        proxy
      end
    end
  end

  class ResourceSet
    class Manager
      Reference = Struct.new(:count, :object) # :nodoc:

      def initialize(create, destroy)
        @mutex = Thread::Mutex.new
        @create = create
        @destroy = destroy
        @ref_table = {}
        @ref_proxy = {}         # to keep proxy objects living in dRuby process
      end

      def key_count
        @mutex.synchronize{ @ref_table.size }
      end

      def ref_count(access_key)
        @mutex.synchronize{
          if (ref = @ref_table[access_key]) then
            ref.count
          else
            0
          end
        }
      end

      def proxy_count
        @mutex.synchronize{ @ref_proxy.length }
      end

      def ref_object?(access_key)
        @mutex.synchronize{
          if (ref = @ref_table[access_key]) then
            ! ref.object.nil?
          else
            false
          end
        }
      end

      def ref_object(access_key)
        @mutex.synchronize{
          if (ref = @ref_table[access_key]) then
            unless (ref.count > 0) then
              raise "internal error: unreferenced resource object <#{ref.count}>"
            end
            ref.count += 1
            ref.object
          else
            # if an exception occurs at `@create.call', the object should not be referenced.
            tmp_object = @create.call(access_key)
            @ref_table[access_key] = Reference.new(1, tmp_object)
            tmp_object
          end
        }
      end

      def unref_object(access_key)
        @mutex.synchronize{
          ref = @ref_table[access_key] or raise "internal error: not defined resource object <#{access_key}>"
          unless (ref.count > 0) then
            raise "internal error: unreferenced resource object <#{ref.count}>"
          end

          ref.count -= 1
          if (ref.count == 0) then
            @ref_table.delete(access_key)
            # even if an exception occurs at `@destroy.call', the object should be unreferenced.
            @destroy.call(ref.object)
          end
        }

        nil
      end

      def ref_proxy(proxy)
        @mutex.synchronize{
          if (@ref_proxy.key? proxy.__id__) then
            raise "internal error: duplicated proxy object <#{proxy.__id__}>"
          end
          @ref_proxy[proxy.__id__] = proxy
        }
      end

      def unref_proxy(proxy)
        @mutex.synchronize{
          @ref_proxy.delete(proxy.__id__) or raise "internal error: unreferenced proxy object <#{proxy.__id__}>"
        }
      end
    end

    class Proxy < Delegator
      include DRb::DRbUndumped
      include Resource::Delegatable
      include Resource::DelegateUnrefAlias

      def initialize(manager, unref_alias_set, access_key)
        @manager = manager
        @unref_alias_set = unref_alias_set
        @access_key = access_key
        # if an exception occurs at `@create.call', the proxy should not be referenced.
        __setobj__(@manager.ref_object(@access_key))
        @manager.ref_proxy(self)
      end

      def __unref__
        delegated = true
        __getobj__{ delegated = false }

        if (delegated) then
          __setobj__(nil)
          @manager.unref_proxy(self)
          # even if an exception occurs at `@destroy.call', the proxy should be unreferenced.
          @manager.unref_object(@access_key)
        end

        nil
      end
    end

    class Builder
      def initialize
        @create = nil
        @destroy = nil
        @unref_alias_set = Set.new
      end

      def at_create(&block)     # :yields: access_key
        @create = block
        nil
      end

      def at_destroy(&block)    # :yields: resource_object
        @destroy = block
        nil
      end

      def alias_unref(name)
        @unref_alias_set << name.to_sym
        nil
      end

      def call
        @create or raise 'not defined create block'
        @destroy or raise 'not defined destroy block'
        ResourceSet.new(Manager.new(@create, @destroy), @unref_alias_set)
      end
    end

    def self.build
      build = Builder.new
      yield(build)
      build.call
    end

    extend Forwardable
    include DRb::DRbUndumped

    def initialize(manager, unref_alias_set)
      @manager = manager
      @unref_alias_set = unref_alias_set
    end

    def_delegators :@manager, :key_count, :ref_count, :proxy_count, :ref_object?

    def call(access_key)
      proxy = Proxy.new(@manager, @unref_alias_set, access_key)
      if (block_given?) then
        begin
          yield(proxy)
        ensure
          proxy.__unref__
        end
      else
        proxy
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
