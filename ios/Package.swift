// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DriverLog",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // An xtool project should contain exactly one library product, representing the app.
        .library(name: "DriverLog", targets: ["DriverLog"]),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
    ],
    targets: [
        // UI-free logic shared with the website's rules: time math, Simple day planner,
        // GPS trip meter, Supabase row mapping. Builds on macOS so it can be unit tested.
        .target(
            name: "DriverLogCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The SwiftUI app.
        .target(
            name: "DriverLog",
            dependencies: [
                "DriverLogCore",
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DriverLogCoreTests",
            dependencies: ["DriverLogCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
