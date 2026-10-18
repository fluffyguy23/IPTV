// swift-tools-version:5.8
import PackageDescription
import Foundation

// libVLC is sourced from the installed VLC.app (3.0.x). The build script can
// override VLC_APP to point elsewhere; default is the standard install path.
let vlcApp = ProcessInfo.processInfo.environment["VLC_APP"] ?? "/Applications/VLC.app"
let vlcInclude = "\(vlcApp)/Contents/MacOS/include"
let vlcLib = "\(vlcApp)/Contents/MacOS/lib"

let package = Package(
    name: "IPTVXtremePlayer",
    platforms: [.macOS(.v12)],
    targets: [
        // C shim exposing a small, stable wrapper around libVLC.
        .target(
            name: "VLCBridge",
            cSettings: [
                .unsafeFlags(["-I\(vlcInclude)"])
            ]
        ),
        // The AppKit application.
        .executableTarget(
            name: "IPTVXtremePlayer",
            dependencies: ["VLCBridge"],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(vlcLib)",
                    "-lvlc",
                    // Resolve @rpath/libvlc.dylib at runtime (dev build points at VLC.app;
                    // the packaged .app also gets @executable_path/../Frameworks added).
                    "-Wl,-rpath,\(vlcLib)",
                    "-Wl,-rpath,@executable_path/../Frameworks"
                ])
            ]
        )
    ]
)
