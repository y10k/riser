# -*- coding: utf-8 -*-

require 'securerandom'
require 'tmpdir'

module Riser
  module TemporaryPath
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
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
