Pod::Spec.new do |s|
  s.name         = "JLNRSessionProtocol"
  s.version      = "0.0.1"
  s.summary      = "NSURLProtocol subclass to transparently handle API session timeouts"

  s.description  = <<-DESC
                   This is an experimental library that tries to isolate API session handling in a centralized place.
                   DESC

  s.homepage     = "https://github.com/jlnr/JLNRSessionProtocol"
  s.license      = "MIT"
  s.author       = { "Julian Raschke" => "julian@raschke.de" }
  s.source       = { git: "https://github.com/jlnr/JLNRSessionProtocol.git" }
  s.source_files = "Classes/**/*.{h,m}"
  s.requires_arc = true

  s.ios.deployment_target  = "8.0"
  s.tvos.deployment_target = "9.0"
  s.osx.deployment_target  = "10.8"
end
