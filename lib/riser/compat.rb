# -*- coding: utf-8 -*-

require 'stringio'

module Riser
  # to use `StringIO' as mock in unit test.  this module provides the
  # refinement to add missing `IO' methods to `StringIO'.
  module CompatibleStringIO
    refine StringIO do
      def to_io
        self
      end

      def to_i
        -1
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
