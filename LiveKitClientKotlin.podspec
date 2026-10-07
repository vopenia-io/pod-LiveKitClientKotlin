Pod::Spec.new do |spec|
  spec.name = "LiveKitClientKotlin"
  spec.version = "2.6.0"
  spec.summary = "Delegate wrapper for Kotlin Multiplatform"
  spec.homepage = "https://github.com/vopenia-io/pod-LiveKitClientKotlin"
  spec.license = {:type => "Apache 2.0", :file => "LICENSE"}
  spec.author = "Vopenia"

  spec.ios.deployment_target = "13.0"
  spec.osx.deployment_target = "10.15"

  spec.swift_versions = ["5.7"]
  spec.source = {:git => "https://github.com/vopenia-io/pod-LiveKitClientKotlin.git", :tag => spec.version.to_s}

  # Swift wrappers only. The BigBlueBetterAudio C/C++ noise-suppression core
  # (RNNoise + Faust + BBBAEngine ObjC++) lives in a dedicated pod (BBBACore)
  # because CocoaPods rejects `../`-relative source paths that escape the pod
  # root. BBBACore is sourced from `:path => ../BigBlueBetterAudio` via the
  # consumer Gradle cocoapods{} block.
  spec.source_files = "LiveKitClientKotlin/Sources/Kotlin/*"

  spec.dependency("LiveKitClient", "2.6.0")
  spec.dependency("BBBACore", "1.0.0")
end
