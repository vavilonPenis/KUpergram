load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "KUpergramExtras",
    module_name = "KUpergramExtras",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    # НЕ ставим -warnings-as-errors: у нас SwiftUI с availability, варнинги не должны ронять сборку
    deps = [],
    visibility = [
        "//visibility:public",
    ],
)
