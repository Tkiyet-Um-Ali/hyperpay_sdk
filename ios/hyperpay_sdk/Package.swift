// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// HyperPay (OPPWA) Mobile SDK binaries for Swift Package Manager.
//
// These are the exact xcframeworks shipped by the `hyperpay_sdk_ios` CocoaPod
// (https://github.com/hrvojecukman/hyperpay_sdk_ios, tag 7.11.0), zipped with
// `ditto -c -k --keepParent` and attached to a GitHub release.
//
// When upgrading the native SDK, upload new zips to a new release and update
// `oppwaVersion` and both checksums (`swift package compute-checksum <zip>`).
let oppwaVersion = "7.11.0"
let binariesBaseURL =
    "https://github.com/Tkiyet-Um-Ali/hyperpay_sdk/releases/download/ios-binaries-\(oppwaVersion)"

let package = Package(
    name: "hyperpay_sdk",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "hyperpay-sdk", targets: ["hyperpay_sdk"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "hyperpay_sdk",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .target(name: "OPPWAMobile"),
                .target(name: "ipworks3ds_sdk"),
            ],
            linkerSettings: [
                .linkedFramework("SafariServices"),
                .linkedFramework("PassKit"),
                .linkedFramework("AuthenticationServices"),
                .linkedFramework("Security"),
                .linkedFramework("WebKit"),
            ]
        ),
        .binaryTarget(
            name: "OPPWAMobile",
            url: "\(binariesBaseURL)/OPPWAMobile.xcframework.zip",
            checksum: "75e17044fc275627d96510a537e62a84bca5d71392a3239b6a044a087b3ec106"
        ),
        .binaryTarget(
            name: "ipworks3ds_sdk",
            url: "\(binariesBaseURL)/ipworks3ds_sdk.xcframework.zip",
            checksum: "49fc7d7a91151c5131ca79fc34dda623227b114acbcbe0c9afc615d9afb6637b"
        ),
    ]
)
