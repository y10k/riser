# -*- coding: utf-8 -*-

require 'riser'
require 'test/unit'

module Riser::Test
  class SocketAddressTest < Test::Unit::TestCase
    data('host:port'       => 'example:80',
         'tcp://host:port' => 'tcp://example:80',
         'Hash:Symbol'     => { type: :tcp, host: 'example', port: 80 },
         'Hash:String'     => { 'type' => 'tcp', 'host' => 'example', 'port' => 80 })
    def test_parse_tcp_socket_address(config)
      addr = Riser::SocketAddress.parse(config)
      assert_instance_of(Riser::TCPSocketAddress, addr)
      assert_equal(:tcp, addr.type)
      assert_equal('example', addr.host)
      assert_equal(80, addr.port)
      assert_equal([ :tcp, 'example', 80 ], addr.to_a)
      assert_equal('tcp:example:80', addr.to_s)
    end

    data('host:port'              => '[::1]:80',
         'tcp://host:port'        => 'tcp://[::1]:80',
         'Hash:Symbol'            => { type: :tcp, host: '::1', port: 80 },
         'Hash:Symbol_SquareHost' => { type: :tcp, host: '[::1]', port: 80 },
         'Hash:String'            => { 'type' => 'tcp', 'host' => '::1', 'port' => 80 },
         'Hash:String_SquareHost' => { 'type' => 'tcp', 'host' => '[::1]', 'port' => 80 })
    def test_parse_tcp_socket_address_ipv6(config)
      addr = Riser::SocketAddress.parse(config)
      assert_instance_of(Riser::TCPSocketAddress, addr)
      assert_equal(:tcp, addr.type)
      assert_equal('::1', addr.host)
      assert_equal(80, addr.port)
      assert_equal([ :tcp, '::1', 80 ], addr.to_a)
      assert_equal('tcp:[::1]:80', addr.to_s)
    end

    data('unix:/path'  => 'unix:/tmp/unix_socket',
         'Hash:Symbol' => { type: :unix, path: '/tmp/unix_socket' },
         'Hash:String' => { 'type' => 'unix', 'path' => '/tmp/unix_socket' })
    def test_parse_unix_socket_address(config)
      addr = Riser::SocketAddress.parse(config)
      assert_instance_of(Riser::UNIXSocketAddress, addr)
      assert_equal(:unix, addr.type)
      assert_equal('/tmp/unix_socket', addr.path)
      assert_equal([ :unix, '/tmp/unix_socket' ], addr.to_a)
      assert_equal('unix:/tmp/unix_socket', addr.to_s)
    end

    data('host_no_port'           => 'host',
         'tcp_uri_no_host'        => 'tcp://:80',
         'tcp_uri_no_port'        => 'tcp://example',
         'unix_uri_no_path'       => 'unix://example',
         'unknown_uri_scheme'     => 'http://example:80',
         'hash_no_type'           => {},
         'hash_tcp_no_host'       => { type: :tcp, port: 80 },
         'hash_tcp_no_port'       => { type: :tcp, host: 'example' },
         'hash_tcp_host_not_str'  => { type: :tcp, host: :example, port: 80 },
         'hash_tcp_port_not_int'  => { type: :tcp, host: 'example', port: '80' },
         'hash_unix_no_path'      => { type: :unix },
         'hash_unix_path_empty'   => { type: :unix, path: '' },
         'hash_unix_path_not_str' => { type: :unix, path: :unix_socket },
         'hash_unknown_type'      => { type: :http, host: 'example', port: 80 })
    def test_fail_to_parse(config)
      assert_nil(Riser::SocketAddress.parse(config))
    end

    tmp_tcp_addr = Riser::SocketAddress.new(type: :tcp, host: 'example', port: 80)
    tmp_unix_addr = Riser::SocketAddress.new(type: :unix, path: '/tmp/unix_socket')
    data('tcp_same'   => [ tmp_tcp_addr, tmp_tcp_addr ],
         'tcp_equal'  => [ Riser::SocketAddress.new(type: :tcp, host: 'example', port: 80),
                           Riser::SocketAddress.new(type: :tcp, host: 'example', port: 80) ],
         'unix_same'  => [ tmp_unix_addr, tmp_unix_addr ],
         'unix_equal' => [ Riser::SocketAddress.new(type: :unix, path: '/tmp/unix_socket'),
                           Riser::SocketAddress.new(type: :unix, path: '/tmp/unix_socket') ])
    def test_equal(data)
      left_addr, right_addr = data
      assert(left_addr == right_addr)
      assert(left_addr.eql? right_addr)
      assert_equal(left_addr.hash, right_addr.hash)
    end

    data('tcp_diff_host'    => [ Riser::SocketAddress.new(type: :tcp, host: 'example',   port: 80),
                                 Riser::SocketAddress.new(type: :tcp, host: 'localhost', port: 80) ],
         'tcp_diff_port'    => [ Riser::SocketAddress.new(type: :tcp, host: 'example', port: 80),
                                 Riser::SocketAddress.new(type: :tcp, host: 'example', port: 8080) ],
         'unix_diff_path'   => [ Riser::SocketAddress.new(type: :unix, path: '/tmp/unix_socket'),
                                 Riser::SocketAddress.new(type: :unix, path: '/tmp/UNIX.SOCKET') ],
         'tcp_not_eq_unix'  => [ Riser::SocketAddress.new(type: :tcp,  host: 'example', port: 80),
                                 Riser::SocketAddress.new(type: :unix, path: '/tmp/unix_socket') ],
         'unix_not_eq_tcp'  => [ Riser::SocketAddress.new(type: :unix, path: '/tmp/unix_socket'),
                                 Riser::SocketAddress.new(type: :tcp,  host: 'example', port: 80) ])
    def test_not_equal(data)
      left_addr, right_addr = data
      assert(left_addr != right_addr)
      assert(! (left_addr.eql? right_addr))
      assert_not_equal(left_addr.hash, right_addr.hash)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
