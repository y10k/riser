# -*- coding: utf-8 -*-

require 'riser/version'

module Riser
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
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
