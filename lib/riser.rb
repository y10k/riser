# -*- coding: utf-8 -*-

require 'riser/version'

module Riser
  autoload :AcceptTimeout, 'riser/server'
  autoload :DRbServiceCall, 'riser/services'
  autoload :DRbServiceServer, 'riser/services'
  autoload :DRbServices, 'riser/services'
  autoload :Daemon, 'riser/daemon'
  autoload :LoggingStream, 'riser/stream'
  autoload :ReadPoll, 'riser/poll'
  autoload :Resource, 'riser/resource'
  autoload :ResourceSet, 'riser/resource'
  autoload :RootProcess, 'riser/daemon'
  autoload :ServerSignal, 'riser/server'
  autoload :SocketAddress, 'riser/sockaddr'
  autoload :SocketServer, 'riser/server'
  autoload :StatusFile, 'riser/daemon'
  autoload :Stream, 'riser/stream'
  autoload :TemporaryPath, 'riser/temppath'
  autoload :TimeoutSizedQueue, 'riser/server'
  autoload :WriteBufferStream, 'riser/stream'

  def preload(namespace=Riser)
    for name in namespace.constants
      if (namespace.autoload? name) then
        namespace.const_get(name)
      end
    end

    nil
  end
  module_function :preload
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
