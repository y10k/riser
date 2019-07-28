# -*- coding: utf-8 -*-

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'riser/version'

Gem::Specification.new do |spec|
  spec.name          = 'riser'
  spec.version       = Riser::VERSION
  spec.authors       = ['TOKI Yoshinori']
  spec.email         = ['toki@freedom.ne.jp']

  spec.summary       = %q{Riser is a library of Ruby Infrastructure for cooperative multi-thread/multi-process SERver}
  spec.description   = <<-'EOF'
    Riser is a library of Ruby Infrastructure for cooperative multi-thread/multi-process SERver.
    This library is useful to make multi-thread/multi-process socket server and daemon.
  EOF
  spec.homepage      = 'https://github.com/y10k/riser'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.16'
  spec.add_development_dependency 'rake', '~> 12.3'
  spec.add_development_dependency 'test-unit', '~> 3.2.7'
  spec.add_development_dependency 'rdoc'
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
