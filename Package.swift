// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DayGhibli",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DayGhibli", targets: ["DayGhibli"])],
    targets: [
        .target(name: "WallpaperCore"),
        .executableTarget(name: "DayGhibli", dependencies: ["WallpaperCore"]),
        .testTarget(name: "DayGhibliTests", dependencies: ["DayGhibli", "WallpaperCore"])
    ]
)
