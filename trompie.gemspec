Gem::Specification.new do |spec|
  spec.name          = "trompie"
  spec.version       = "0.1.0"
  spec.authors       = ["entropie"]
  spec.summary       = "HA & MQTT"
  spec.files         = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]
  spec.add_dependency "mqtt"
end
