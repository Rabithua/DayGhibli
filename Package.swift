// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DayGhibli",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DayGhibli", targets: ["DayGhibli"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(name: "WallpaperCore"),
        .executableTarget(name: "DayGhibli", dependencies: [
            "WallpaperCore", .product(name: "Sparkle", package: "Sparkle")
        ], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "DayGhibliTests", dependencies: ["DayGhibli", "WallpaperCore"])
    ]
)
