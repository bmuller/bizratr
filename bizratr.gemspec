$:.push File.expand_path("../lib", __FILE__)
require "bizratr/version"
require "rake"
require "date"

Gem::Specification.new do |s|
  s.name = "bizratr"
  s.version = BizRatr::VERSION
  s.authors = ["Brian Muller"]
  s.date = Date.today.to_s
  s.description = "Get business ratings."
  s.summary = "Get business ratings."
  s.email = "bamuller@gmail.com"
  s.files = FileList["lib/**/*", "[A-Z]*", "Rakefile", "docs/**/*"]
  s.homepage = "http://findingscience.com/bizratr"
  s.require_paths = ["lib"]
  s.required_ruby_version = Gem::Requirement.new(">= 1.9.0")
  s.add_dependency('foursquare2')
  s.add_dependency('yelpster')
  s.add_dependency('google_places')
  s.add_dependency('levenshtein')
  s.add_dependency('google_places')
  s.add_dependency('geocoder')
  s.add_dependency('koala')
  s.add_dependency('factual-api')
  s.rubyforge_project = "bizratr"
end
