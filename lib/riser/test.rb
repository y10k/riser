# -*- coding: utf-8 -*-

module Riser
  module Test
    class CallRecorder
      def initialize(store_path)
        @memory_records = []
        @file_records = store_path
      end

      def call(record)
        @memory_records << record
        IO.write(@file_records, record + "\n", mode: 'a')
        self
      end

      def get_memory_records
        @memory_records
      end

      def get_file_records
        if (File.exist? @file_records) then
          IO.readlines(@file_records).map{|line| line.chomp }
        else
          []
        end
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
