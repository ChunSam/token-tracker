#!/usr/bin/env swift
import AppKit

// Release-path smoke for the macOS app bundle, the counterpart to the Windows
// publish smoke in CI.
//
// `swift build` proves the code compiles; it says nothing about whether the .app
// scripts/build_app.sh assembles can find its own resources. It could not: the
// resource bundle sat in Contents/Resources while the executable looked beside its
// bundle and in the build directory baked in at compile time. On a build machine
// that directory still exists, so every local run looked fine and every release DMG
// trapped on the first icon-style render.
//
// So assert what only a packaged app can answer: the bundle is inside
// Contents/Resources, and its icons decode from there — no build directory in reach.

let appPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".build/Token Tracker.app"
let appURL = URL(fileURLWithPath: appPath)
var failures: [String] = []

func check(_ condition: Bool, _ message: String) {
    if !condition { failures.append(message) }
}

let executableURL = appURL.appendingPathComponent("Contents/MacOS/TokenTrackerMenuBar")
check(FileManager.default.isExecutableFile(atPath: executableURL.path), "missing executable at \(executableURL.path)")

let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
if let info = NSDictionary(contentsOf: infoPlistURL) {
    check(info["CFBundleShortVersionString"] is String, "Info.plist has no CFBundleShortVersionString")
    check(info["CFBundleVersion"] is String, "Info.plist has no CFBundleVersion")
    check(info["CFBundleIdentifier"] is String, "Info.plist has no CFBundleIdentifier")
} else {
    failures.append("unreadable Info.plist at \(infoPlistURL.path)")
}

// The bundle has to be reachable the way the app reaches it — from the app's own
// resources, not from wherever it happened to be built.
let resourceBundleURL = appURL
    .appendingPathComponent("Contents/Resources")
    .appendingPathComponent("TokenTrackerMenuBar_TokenTrackerMenuBar.bundle")
if let resourceBundle = Bundle(url: resourceBundleURL) {
    for icon in ["claudeTemplate@2x", "codexTemplate@2x"] {
        guard let url = resourceBundle.url(forResource: icon, withExtension: "png") else {
            failures.append("\(icon).png is not in the packaged resource bundle")
            continue
        }
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
            failures.append("\(icon).png did not decode from the packaged resource bundle")
            continue
        }
    }
} else {
    failures.append("no resource bundle at \(resourceBundleURL.path)")
}

guard failures.isEmpty else {
    for failure in failures { FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8)) }
    exit(1)
}

print("App bundle smoke passed: \(appURL.lastPathComponent)")
