load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "Facegram",
    module_name = "Facegram",
    srcs = glob([
		"Facegram/**/*.swift",
    ]),
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/SyncCore:SyncCore",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/AnimationUI:AnimationUI",
        "//submodules/AppBundle:AppBundle",
    ],
    visibility = [
        "//visibility:public",
    ],
)
