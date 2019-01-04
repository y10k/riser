# -*- coding: utf-8 -*-

require 'riser/version'

module Riser
  autoload :DRbServiceCall, 'riser/services'
  autoload :DRbServiceServer, 'riser/services'
  autoload :DRbServices, 'riser/services'
  autoload :LoggingStream, 'riser/stream'
  autoload :PullBuffer, 'riser/server'
  autoload :ReadPoll, 'riser/poll'
  autoload :Stream, 'riser/stream'
  autoload :WriteBufferStream, 'riser/stream'
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
