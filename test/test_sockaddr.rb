# -*- coding: utf-8 -*-

require 'riser'
require 'socket'
require 'test/unit'
require 'uri'

module Riser::Test
  class SocketAddressTest < Test::Unit::TestCase
    data('host:port'               => 'example:80',
         'tcp://host:port'         => 'tcp://example:80',
         'Hash:Symbol'             => { type: :tcp, host: 'example', port: 80 },
         'Hash:Symbol_svc_name'    => { type: :tcp, host: 'example', port: 'http' },
         'Hash:Symbol_backlog_nil' => { type: :tcp, host: 'example', port: 80, backlog: nil },
         'Hash:String'             => { 'type' => 'tcp', 'host' => 'example', 'port' => 80 },
         'Hash:String_svc_name'    => { 'type' => 'tcp', 'host' => 'example', 'port' => 'http' },
         'Hash:String_backlog_nil' => { 'type' => 'tcp', 'host' => 'example', 'port' => 80, 'backlog' => nil })
    def test_parse_tcp_socket_address(config)
      addr = Riser::SocketAddress.parse(config)
      assert_instance_of(Riser::TCPSocketAddress, addr)
      assert_equal(:tcp, addr.type)
      assert_equal('example', addr.host)
      assert_equal(80, addr.port)
      assert_equal([ :tcp, 'example', 80 ], addr.to_address)
      assert_equal('tcp://example:80', addr.to_s)
      assert_equal({}, addr.to_option)
      assert_nil(addr.backlog)
    end

    data('host:port'               => '[::1]:80',
         'tcp://host:port'         => 'tcp://[::1]:80',
         'Hash:Symbol'             => { type: :tcp, host: '::1', port: 80 },
         'Hash:Symbol_SquareHost'  => { type: :tcp, host: '[::1]', port: 80 },
         'Hash:Symbol_svc_name'    => { type: :tcp, host: '::1', port: 'http' },
         'Hash:Symbol_backlog_nil' => { type: :tcp, host: '::1', port: 80, backlog: nil },
         'Hash:String'             => { 'type' => 'tcp', 'host' => '::1', 'port' => 80 },
         'Hash:String_SquareHost'  => { 'type' => 'tcp', 'host' => '[::1]', 'port' => 80 },
         'Hash:String_svc_name'    => { 'type' => 'tcp', 'host' => '::1', 'port' => 'http' },
         'Hash:String_backlog_nil' => { 'type' => 'tcp', 'host' => '[::1]', 'port' => 80, 'backlog' => nil })
    def test_parse_tcp_socket_address_ipv6(config)
      addr = Riser::SocketAddress.parse(config)
      assert_instance_of(Riser::TCPSocketAddress, addr)
      assert_equal(:tcp, addr.type)
      assert_equal('::1', addr.host)
      assert_equal(80, addr.port)
      assert_equal([ :tcp, '::1', 80 ], addr.to_address)
      assert_equal('tcp://[::1]:80', addr.to_s)
      assert_equal({}, addr.to_option)
      assert_nil(addr.backlog)
    end

    data('Hash:Symbol'     => { type: :tcp, host: 'example', port: 80, backlog: 5 },
         'Hash:String'     => { 'type' => 'tcp', 'host' => 'example', 'port' => 80, 'backlog' => 5 })
    def test_parse_tcp_socket_address_backlog(config)
      addr = Riser::SocketAddress.parse(config)
      assert_instance_of(Riser::TCPSocketAddress, addr)
      assert_equal(:tcp, addr.type)
      assert_equal('example', addr.host)
      assert_equal(80, addr.port)
      assert_equal([ :tcp, 'example', 80 ], addr.to_address)
      assert_equal('tcp://example:80', addr.to_s)
      assert_equal({ backlog: 5 }, addr.to_option)
      assert_equal(5, addr.backlog)
    end

    data('unix:/path'  => 'unix:/tmp/unix_socket',
         'Hash:Symbol' => { type: :unix, path: '/tmp/unix_socket' },
         'Hash:String' => { 'type' => 'unix', 'path' => '/tmp/unix_socket' })
    def test_parse_unix_socket_address(config)
      addr = Riser::SocketAddress.parse(config)
      assert_instance_of(Riser::UNIXSocketAddress, addr)
      assert_equal(:unix, addr.type)
      assert_equal('/tmp/unix_socket', addr.path)
      assert_equal([ :unix, '/tmp/unix_socket' ], addr.to_address)
      assert_equal('unix:/tmp/unix_socket', addr.to_s)
      assert_equal({}, addr.to_option)
      assert_nil(addr.backlog)
      assert_nil(addr.mode)
      assert_nil(addr.owner)
      assert_nil(addr.group)
    end

    data('Hash:Symbol' => { type: :unix, path: '/tmp/unix_socket', backlog: 5 },
         'Hash:String' => { 'type' => 'unix', 'path' => '/tmp/unix_socket', 'backlog' => 5 })
    def test_parse_unix_socket_address_backlog(config)
      addr = Riser::SocketAddress.parse(config)
      assert_instance_of(Riser::UNIXSocketAddress, addr)
      assert_equal(:unix, addr.type)
      assert_equal('/tmp/unix_socket', addr.path)
      assert_equal([ :unix, '/tmp/unix_socket' ], addr.to_address)
      assert_equal('unix:/tmp/unix_socket', addr.to_s)
      assert_equal({ backlog: 5 }, addr.to_option)
      assert_equal(5, addr.backlog)
      assert_nil(addr.mode)
      assert_nil(addr.owner)
      assert_nil(addr.group)
    end

    data('Hash:Symbol' => { type: :unix, path: '/tmp/unix_socket', mode: 0600 },
         'Hash:String' => { 'type' => 'unix', 'path' => '/tmp/unix_socket', 'mode' => 0600 })
    def test_parse_unix_socket_address_mode(config)
      addr = Riser::SocketAddress.parse(config)
      assert_instance_of(Riser::UNIXSocketAddress, addr)
      assert_equal(:unix, addr.type)
      assert_equal('/tmp/unix_socket', addr.path)
      assert_equal([ :unix, '/tmp/unix_socket' ], addr.to_address)
      assert_equal('unix:/tmp/unix_socket', addr.to_s)
      assert_equal({ mode: 0600 }, addr.to_option)
      assert_nil(addr.backlog)
      assert_equal(0600, addr.mode)
      assert_nil(addr.owner)
      assert_nil(addr.group)
    end

    data('Hash:Symbol' => { type: :unix, path: '/tmp/unix_socket', owner: 0, group: 1 },
         'Hash:String' => { 'type' => 'unix', 'path' => '/tmp/unix_socket', 'owner' => 0, 'group' => 1 })
    def test_parse_unix_socket_address_owner_group_integer(config)
      addr = Riser::SocketAddress.parse(config)
      assert_instance_of(Riser::UNIXSocketAddress, addr)
      assert_equal(:unix, addr.type)
      assert_equal('/tmp/unix_socket', addr.path)
      assert_equal([ :unix, '/tmp/unix_socket' ], addr.to_address)
      assert_equal('unix:/tmp/unix_socket', addr.to_s)
      assert_equal({ owner: 0, group: 1 }, addr.to_option)
      assert_nil(addr.backlog)
      assert_nil(addr.mode)
      assert_equal(0, addr.owner)
      assert_equal(1, addr.group)
    end

    data('Hash:Symbol' => { type: :unix, path: '/tmp/unix_socket', owner: 'root', group: 'wheel' },
         'Hash:String' => { 'type' => 'unix', 'path' => '/tmp/unix_socket', 'owner' => 'root', 'group' => 'wheel' })
    def test_parse_unix_socket_address_owner_group_string(config)
      addr = Riser::SocketAddress.parse(config)
      assert_instance_of(Riser::UNIXSocketAddress, addr)
      assert_equal(:unix, addr.type)
      assert_equal('/tmp/unix_socket', addr.path)
      assert_equal([ :unix, '/tmp/unix_socket' ], addr.to_address)
      assert_equal('unix:/tmp/unix_socket', addr.to_s)
      assert_equal({ owner: 'root', group: 'wheel' }, addr.to_option)
      assert_nil(addr.backlog)
      assert_nil(addr.mode)
      assert_equal('root', addr.owner)
      assert_equal('wheel', addr.group)
    end

    data('tcp_bad_uri'               => [ 'tcp://"example"',
                                          URI::InvalidURIError ],
         'tcp_uri_no_host'           => [ 'tcp://:80',
                                          ArgumentError, 'need for a tcp socket uri host.' ],
         'tcp_uri_no_port'           => [ 'tcp://example',
                                          ArgumentError, 'need for a tcp socket uri port.' ],
         'unix_bad_uri'              => [ 'unix:"/tmp/unix_socket"',
                                          URI::InvalidURIError ],
         'unix_uri_no_path'          => [ 'unix:example',
                                          ArgumentError, 'need for a unix socket uri path.' ],
         'unix_uri_path_empty'       => [ 'unix:',
                                          ArgumentError, 'empty unix socket uri path.' ],
         'hash_tcp_no_host'          => [ { type: :tcp, port: 80 },
                                          ArgumentError, 'need for a tcp socket host.' ],
         'hash_tcp_host_not_str'     => [ { type: :tcp, host: :example, port: 80 },
                                          TypeError, 'not a string tcp scoket host.' ],
         'hash_tcp_host_empty'       => [ { type: :tcp, host: '', port: 80 },
                                          ArgumentError, 'empty tcp socket host.' ],
         'hash_tcp_no_port'          => [ { type: :tcp, host: 'example' },
                                          ArgumentError, 'need for a tcp socket port.' ],
         'hash_tcp_port_not_int'     => [ { type: :tcp, host: 'example', port: :http },
                                          TypeError, 'port number is neither an integer nor a service name.' ],
         'hash_tcp_port_bad_svc'     => [ { type: :tcp, host: 'example', port: 'nothing' },
                                          SocketError ],
         'hash_tcp_backlog_not_int'  => [ { type: :tcp, host: 'example', port: 80, backlog: '5' },
                                          TypeError, 'not a integer tcp socket backlog.' ],
         'hash_unix_no_path'         => [ { type: :unix },
                                          ArgumentError, 'need for a unix socket path.' ],
         'hash_unix_path_not_str'    => [ { type: :unix, path: :unix_socket },
                                          TypeError, 'not a string unix socket path.' ],
         'hash_unix_path_empty'      => [ { type: :unix, path: '' },
                                          ArgumentError, 'empty unix socket path.' ],
         'hash_unix_backlog_not_int' => [ { type: :unix, path: '/tmp/unix_socket', backlog: '5' },
                                          TypeError, 'not a integer unix socket backlog.' ],
         'hash_unix_mode_not_int'    => [ { type: :unix, path: '/tmp/unix_socket', mode: '0600' },
                                          TypeError, 'not a integer socket mode.' ],
         'hash_unix_owner_not_str'   => [ { type: :unix, path: '/tmp/unix_socket', owner: :root },
                                          TypeError, 'unix socket owner is neither an integer nor a string.' ],
         'hash_unix_owner_empty'     => [ { type: :unix, path: '/tmp/unix_socket', owner: '' },
                                          ArgumentError, 'empty unix socket owner.' ],
         'hash_unix_group_not_str'   => [ { type: :unix, path: '/tmp/unix_socket', group: :wheel },
                                          TypeError, 'unix socket group is neither an integer nor a string.' ],
         'hash_unix_group_empty'     => [ { type: :unix, path: '/tmp/unix_socket', group: '' },
                                          ArgumentError, 'empty unix socket group.' ],
         'unknown_uri_scheme'        => [ 'http://example:80',
                                          ArgumentError, 'invalid socket address.' ],
         'host_no_port'              => [ 'host',
                                          ArgumentError, 'invalid socket address.' ],
         'hash_no_type'              => [ {},
                                          ArgumentError, 'invalid socket address.' ],
         'hash_unknown_type'         => [ { type: :http, host: 'example', port: 80 },
                                          ArgumentError, 'invalid socket address.' ],
         'invalid_address_object'    => [ Object.new,
                                          ArgumentError, 'invalid socket address.' ])
    def test_fail_to_parse(data)
      config, expected_error, expected_message = data
      error = assert_raise(expected_error) { assert_nil(Riser::SocketAddress.parse(config)) }
      assert_equal(expected_message, error.message) if expected_message
    end

    tmp_tcp_addr = Riser::SocketAddress.parse(type: :tcp, host: 'example', port: 80)
    tmp_unix_addr = Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket')
    data('tcp_same'        => [ tmp_tcp_addr, tmp_tcp_addr ],
         'tcp_equal'       => [ Riser::SocketAddress.parse(type: :tcp, host: 'example', port: 80),
                                Riser::SocketAddress.parse(type: :tcp, host: 'example', port: 80) ],
         'tcp_eq_backlog'  => [ Riser::SocketAddress.parse(type: :tcp, host: 'example', port: 80, backlog: 5),
                                Riser::SocketAddress.parse(type: :tcp, host: 'example', port: 80, backlog: 5) ],
         'unix_same'       => [ tmp_unix_addr, tmp_unix_addr ],
         'unix_equal'      => [ Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket'),
                                Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket') ],
         'unix_eq_backlog' => [ Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket', backlog: 5),
                                Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket', backlog: 5) ],
         'unix_eq_perm'    => [ Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket', mode: 0600, owner: 'root', group: 'wheel'),
                                Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket', mode: 0600, owner: 'root', group: 'wheel') ])
    def test_equal(data)
      left_addr, right_addr = data
      assert(left_addr == right_addr)
      assert(left_addr.eql? right_addr)
      assert_equal(left_addr.hash, right_addr.hash)
    end

    data('tcp_diff_host'     => [ Riser::SocketAddress.parse(type: :tcp, host: 'example',   port: 80),
                                  Riser::SocketAddress.parse(type: :tcp, host: 'localhost', port: 80) ],
         'tcp_diff_port'     => [ Riser::SocketAddress.parse(type: :tcp, host: 'example', port: 80),
                                  Riser::SocketAddress.parse(type: :tcp, host: 'example', port: 8080) ],
         'tcp_diff_backlog'  => [ Riser::SocketAddress.parse(type: :tcp, host: 'example', port: 80, backlog: 5),
                                  Riser::SocketAddress.parse(type: :tcp, host: 'example', port: 80, backlog: 8) ],
         'unix_diff_path'    => [ Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket'),
                                  Riser::SocketAddress.parse(type: :unix, path: '/tmp/UNIX.SOCKET') ],
         'unix_diff_backlog' => [ Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket', backlog: 5),
                                  Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket', backlog: 8) ],
         'unix_diff_mode'    => [ Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket', mode: 0600, owner: 'root', group: 'wheel'),
                                  Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket', mode: 0666, owner: 'root', group: 'wheel') ],
         'unix_diff_owner'   => [ Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket', mode: 0600, owner: 'root', group: 'wheel'),
                                  Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket', mode: 0600, owner: 'user', group: 'wheel') ],
         'unix_diff_group'   => [ Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket', mode: 0600, owner: 'root', group: 'wheel'),
                                  Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket', mode: 0600, owner: 'root', group: 'user') ],
         'tcp_not_eq_unix'   => [ Riser::SocketAddress.parse(type: :tcp,  host: 'example', port: 80),
                                  Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket') ],
         'unix_not_eq_tcp'   => [ Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket'),
                                  Riser::SocketAddress.parse(type: :tcp,  host: 'example', port: 80) ])
    def test_not_equal(data)
      left_addr, right_addr = data
      assert(left_addr != right_addr)
      assert(! (left_addr.eql? right_addr))
      assert_not_equal(left_addr.hash, right_addr.hash)
    end

    data('tcp_addr'  => Riser::SocketAddress.parse(type: :tcp, host: 'example', port: 80),
         'unix_addr' => Riser::SocketAddress.parse(type: :unix, path: '/tmp/unix_socket'))
    def test_not_equal_object(data)
      addr = data
      assert(addr != Object.new)
      assert(Object.new != addr)
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
