# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'qpx/version'

Gem::Specification.new do |spec|
  spec.name          = "qpx"
  spec.version       = Qpx::VERSION
  spec.authors       = ["Yawo KPOTUFE"]
  spec.email         = ["mcguy2008@gmail.com"]
  spec.summary       = %q{Google QPX QPI}
  spec.description   = %q{Google QPX Ruby API}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "nokogiri"
  spec.add_development_dependency "mongo"
  spec.add_development_dependency "bson_ext"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rack-cache"
  spec.add_runtime_dependency "rest-client"
  spec.add_runtime_dependency "rest-client-components"
  
  
end
