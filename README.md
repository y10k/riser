Riser
=====

RISER is a library of **R**uby **I**nfrastructure for cooperative
multi-thread/multi-process **SER**ver.

This library is useful for the following.

* to make a server with tcp/ip or unix domain socket
* to choose a method to execute server from:
    - single process multi-thread
	- preforked multi-process multi-thread
* to make a daemon that wil be controlled by signal(2)s
* to separate singleton task not divided into multiple processes from
  server process(es) into backend service process

This library supposes that the user is familiar with the unix process
model and socket programming.

Installation
------------

Add this line to your application's Gemfile:

```ruby
gem 'riser'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install riser

Usage
-----

TODO: Write usage instructions here

Development
-----------

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

Contributing
------------

Bug reports and pull requests are welcome on GitHub at <https://github.com/y10k/riser>.

License
-------

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
