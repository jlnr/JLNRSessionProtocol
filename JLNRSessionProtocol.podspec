Pod::Spec.new do |s|
  s.name         = "JLNRSessionProtocol"
  s.version      = "0.0.1"
  s.summary      = "NSURLProtocol subclass for customisable API session management"

  s.description  = <<-DESC
                   TODO
                   DESC

  s.homepage     = "https://github.com/jlnr/JLNRSessionProtocol"
  s.license      = "MIT"
  s.author       = { "Julian Raschke" => "julian@raschke.de" }
  s.platform     = :ios, "5.0"
  s.source       = { :git => "https://github.com/jlnr/JLNRSessionProtocol.git" }
  s.source_files = "Classes/**/*.{h,m}"
  s.requires_arc = true
end
