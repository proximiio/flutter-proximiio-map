#
# CocoaPods spec. The Proximi.io map library ships only as a Swift package, so under CocoaPods the
# plugin compiles without it and each map shows a notice that Swift Package Manager is required.
# Turn on Flutter's Swift Package Manager support to get the map:
#
#   flutter config --enable-swift-package-manager
#
Pod::Spec.new do |s|
  s.name             = 'flutter_proximiio_map'
  s.version          = '6.0.0-beta.6'
  s.summary          = 'Proximi.io venue map for Flutter (platform view over the Proximi.io iOS Map v6).'
  s.description      = <<-DESC
Flutter platform view over the Proximi.io iOS Map v6: venue map, floors, routes, guidance and journeys.
Needs Flutter's Swift Package Manager support; under CocoaPods it builds a notice only.
                       DESC
  s.homepage         = 'https://github.com/proximiio/flutter-proximiio-map'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Proximi.io' => 'support@proximi.io' }
  s.source           = { :path => '.' }
  s.source_files     = 'flutter_proximiio_map/Sources/flutter_proximiio_map/**/*.swift'
  s.resource_bundles = { 'flutter_proximiio_map_privacy' => ['flutter_proximiio_map/Sources/flutter_proximiio_map/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.0'
end
