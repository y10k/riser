# -*- coding: utf-8 -*-

require 'riser/version'

module Riser
  autoload :DRbServiceCall, 'riser/services'
  autoload :DRbServiceServer, 'riser/services'
  autoload :DRbServices, 'riser/services'
  autoload :LoggingStream, 'riser/stream'
  autoload :ReadPoll, 'riser/poll'
  autoload :SocketAddress, 'riser/server'
  autoload :SocketServer, 'riser/server'
  autoload :Stream, 'riser/stream'
  autoload :TCPSocketAddress, 'riser/server'
  autoload :TemporaryPath, 'riser/temppath'
  autoload :TimeoutSizedQueue, 'riser/server'
  autoload :UNIXSocketAddress, 'riser/server'
  autoload :WriteBufferStream, 'riser/stream'
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
