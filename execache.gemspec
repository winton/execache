# -*- encoding: utf-8 -*-
root = File.expand_path('../', __FILE__)
lib = "#{root}/lib"

$:.unshift lib unless $:.include?(lib)

Gem::Specification.new do |s|
  s.name        = "execache"
  s.version     = '0.1.0'
  s.platform    = Gem::Platform::RUBY
  s.authors     = [ "Winton Welsh" ]
  s.email       = [ "mail@wintoni.us" ]
  s.homepage    = "http://github.com/winton/execache"
  s.summary     = %q{Run commands in parallel and cache the output, controlled by Redis}
  s.description = %q{Run commands in parallel and cache the output. Redis queues jobs and stores the result.}

  s.executables = `cd #{root} && git ls-files bin/*`.split("\n").collect { |f| File.basename(f) }
  s.files = `cd #{root} && git ls-files`.split("\n")
  s.require_paths = %w(lib)
  s.test_files = `cd #{root} && git ls-files -- {features,test,spec}/*`.split("\n")

  s.add_development_dependency "rspec", "~> 1.0"

  s.add_dependency "redis", "~> 2.2.2"
  s.add_dependency "yajl-ruby", "~> 1.0.0"
end