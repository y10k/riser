# -*- coding: utf-8 -*-

require 'riser'
require 'test/unit'
require 'uri'

module Riser::Test
  class TemporaryPathTest < Test::Unit::TestCase
    def setup
      @try_count = 10
    end

    def test_make_unix_socket_path
      temp_path_list = []
      @try_count.times do
        temp_path_list << Riser::TemporaryPath.make_unix_socket_path
      end

      assert_equal(temp_path_list, temp_path_list.uniq)
      temp_path_list.each_with_index do |temp_path, i|
        temp_path = Riser::TemporaryPath.make_unix_socket_path
        assert(! (File.exist? temp_path), "count: #{i}, path: #{temp_path}")
        assert((File.directory? File.dirname(temp_path)), "count: #{i}, path: #{temp_path}")
      end
    end

    def test_make_drbunix_uri
      temp_uri_list = []
      @try_count.times do
        temp_uri_list << URI(Riser::TemporaryPath.make_drbunix_uri)
      end

      assert_equal(temp_uri_list, temp_uri_list.uniq)
      temp_uri_list.each_with_index do |temp_uri, i|
        assert_equal('drbunix', temp_uri.scheme, "count: #{i}, uri: #{temp_uri}")
        assert(! (File.exist? temp_uri.path), "count: #{i}, uri: #{temp_uri}")
        assert((File.directory? File.dirname(temp_uri.path)), "count: #{i}, uri: #{temp_uri}")
      end
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
