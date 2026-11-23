import CryptoKit
import Foundation
import Testing

// The install command (docs/specs/20-install-command.md). These tests run the real
// `scripts/install.sh` template, rendered by the real `scripts/render-install.sh`, against small
// disk images. Nothing touches /Applications: every run is rendered with a temporary destination,
// a local image and "do not open". `scripts/release.sh --dry-run` runs the same script against
// the real release image (DST-20).

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private let bundleID = "io.github.bakhtiyor7.WhoIsWorking"
private let lockName = ".WhoIsWorking.install.lock"

private struct Ran {
    let status: Int32
    let out: String
    let err: String
    var all: String { out + err }
}

@discardableResult
private func run(_ tool: String, _ arguments: [String], environment: [String: String] = [:]) throws -> Ran {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = arguments
    p.currentDirectoryURL = repoRoot
    p.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory()]
        .merging(environment) { _, new in new }
    let out = Pipe(), err = Pipe()
    p.standardInput = FileHandle.nullDevice
    p.standardOutput = out
    p.standardError = err
    try p.run()
    let outText = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let errText = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    p.waitUntilExit()
    return Ran(status: p.terminationStatus, out: outText, err: errText)
}

private struct Failed: Error, CustomStringConvertible {
    let description: String
}

private func must(_ tool: String, _ arguments: [String]) throws {
    let r = try run(tool, arguments)
    guard r.status == 0 else {
        throw Failed(description: "\(tool) \(arguments.joined(separator: " ")) exited \(r.status): \(r.all)")
    }
}

private func newDir(_ name: String, in parent: URL = FileManager.default.temporaryDirectory) throws -> URL {
    let dir = parent.appendingPathComponent("wiw-install-\(name)-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func sha256(_ url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
}

/// A stand-in app bundle: the right layout, a real executable named WhoIsWorking that only sleeps,
/// and an ad-hoc signature, as the released app has.
private func makeApp(in dir: URL, version: String, id: String = bundleID, helper: URL) throws -> URL {
    let app = dir.appendingPathComponent("WhoIsWorking.app")
    let macOS = app.appendingPathComponent("Contents/MacOS")
    try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: helper, to: macOS.appendingPathComponent("WhoIsWorking"))
    let plist: [String: Any] = [
        "CFBundleIdentifier": id, "CFBundleExecutable": "WhoIsWorking", "CFBundleName": "WhoIsWorking",
        "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version, "CFBundleVersion": "1",
    ]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: app.appendingPathComponent("Contents/Info.plist"))
    try must("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
    return app
}

private func installedVersion(_ app: URL) -> String? {
    guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else { return nil }
    return plist["CFBundleShortVersionString"] as? String
}

/// Disk images shared by the suite; building them is the slow part.
private struct Fixtures: Sendable {
    let helper: URL
    let v010: URL
    let v020: URL
    let wrongID: URL
    let quarantined: URL

    static func build() throws -> Fixtures {
        let dir = try newDir("fixtures")
        // The images are shared by every test, so they go when the test process exits.
        fixturesPath = dir.path
        atexit { if let path = fixturesPath { try? FileManager.default.removeItem(atPath: path) } }
        let source = dir.appendingPathComponent("helper.c")
        try """
        #include <stdlib.h>
        #include <unistd.h>
        int main(int argc, char **argv) { sleep(argc > 1 ? (unsigned)atoi(argv[1]) : 0); return 0; }
        """.write(to: source, atomically: true, encoding: .utf8)
        let helper = dir.appendingPathComponent("helper")
        try must("/usr/bin/xcrun", ["cc", "-o", helper.path, source.path])

        // `hdiutil create -srcfolder`, which scripts/make-dmg.sh uses, takes about 4 s whatever the
        // size. So one blank image is made here (1 s) and each fixture is a copy of it with an app
        // put inside, which also keeps extended attributes such as quarantine.
        let blank = dir.appendingPathComponent("blank.dmg")
        try must("/usr/bin/hdiutil", [
            "create", "-quiet", "-size", "2m", "-fs", "HFS+", "-volname", "WhoIsWorking", "-layout", "NONE", blank.path,
        ])
        func image(_ name: String, version: String, id: String = bundleID, quarantine: Bool = false) throws -> URL {
            let stage = dir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            let app = try makeApp(in: stage, version: version, id: id, helper: helper)
            if quarantine {
                try must("/usr/bin/xattr", ["-w", "com.apple.quarantine", "0081;00000000;Safari;", app.path])
            }
            let dmg = dir.appendingPathComponent("\(name).dmg")
            try FileManager.default.copyItem(at: blank, to: dmg)
            let mount = dir.appendingPathComponent("\(name)-mount")
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            try must("/usr/bin/hdiutil", [
                "attach", "-quiet", "-noverify", "-nobrowse", "-noautoopen", "-mountpoint", mount.path, dmg.path,
            ])
            do {
                try must("/usr/bin/ditto", [app.path, mount.appendingPathComponent("WhoIsWorking.app").path])
                // The released image has this link beside the app; the installer must not follow it.
                try FileManager.default.createSymbolicLink(
                    atPath: mount.appendingPathComponent("Applications").path, withDestinationPath: "/Applications")
            } catch {
                _ = try? run("/usr/bin/hdiutil", ["detach", "-quiet", "-force", mount.path])
                throw error
            }
            try must("/usr/bin/hdiutil", ["detach", "-quiet", mount.path])
            return dmg
        }
        return Fixtures(
            helper: helper,
            v010: try image("v010", version: "0.1.0"),
            v020: try image("v020", version: "0.2.0"),
            wrongID: try image("wrong-id", version: "0.2.0", id: "com.example.Other"),
            quarantined: try image("quarantined", version: "0.2.0", quarantine: true))
    }
}

private nonisolated(unsafe) var fixturesPath: String?
private let fixtures = Result { try Fixtures.build() }

/// One test's world: a destination standing in for /Applications and a private TMPDIR.
private struct Box {
    let root: URL
    let dest: URL
    let tmp: URL
    var app: URL { dest.appendingPathComponent("WhoIsWorking.app") }
    var lock: URL { dest.appendingPathComponent(lockName) }

    init(in parent: URL) throws {
        root = try newDir("box", in: parent)
        dest = root.appendingPathComponent("Applications")
        tmp = root.appendingPathComponent("tmp")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    func render(
        version: String, sha: String, minMacOS: String = "15.0", url: String, proto: String = "=file",
        open: Bool = false
    ) throws -> URL {
        let r = try run("/bin/sh", [
            "scripts/render-install.sh", version, sha, minMacOS,
            "DEST=\(dest.path)", "DMG_URL=\(url)", "PROTO=\(proto)", "OPEN=\(open ? 1 : 0)",
        ])
        guard r.status == 0 else { throw Failed(description: "render failed: \(r.err)") }
        let script = root.appendingPathComponent("install-\(UUID().uuidString.prefix(6)).sh")
        try r.out.write(to: script, atomically: true, encoding: .utf8)
        return script
    }

    /// Renders the template for `dmg` and runs it. `open: true` renders the published behaviour;
    /// use it only where the script must decide *not* to open the app.
    func install(
        _ dmg: URL, version: String, sha: String? = nil, minMacOS: String = "15.0", open: Bool = false,
        environment: [String: String] = [:]
    ) throws -> Ran {
        let script = try render(
            version: version, sha: try sha ?? sha256(dmg), minMacOS: minMacOS, url: "file://\(dmg.path)", open: open)
        return try run("/bin/sh", [script.path], environment: ["TMPDIR": tmp.path].merging(environment) { _, new in new })
    }

    func leftInTmp() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: tmp.path)
    }

    /// What the installer has of its own in the destination: its lock and staging folders.
    func installerEntries() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dest.path)
            .filter { $0.hasPrefix(".WhoIsWorking.install") }.sorted()
    }

    /// A pid that belongs to no process: a helper that has already exited.
    func deadPid(_ helper: URL) throws -> Int32 {
        let p = try start(helper, seconds: 0)
        p.waitUntilExit()
        return p.processIdentifier
    }
}

private func start(_ executable: URL, seconds: Int = 30) throws -> Process {
    let p = Process()
    p.executableURL = executable
    p.arguments = [String(seconds)]
    p.standardInput = FileHandle.nullDevice
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try p.run()
    return p
}

@Suite("Install script", .serialized)
final class InstallScriptTests {
    /// Everything a test makes lives under here and goes when the test ends.
    private let scratch: URL

    init() throws {
        scratch = try newDir("test")
    }

    deinit {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func newBox() throws -> Box { try Box(in: scratch) }

    // MARK: Rendering (DST-13, DST-19)

    @Test func thePublishedRenderingIsPinnedToItsRelease() throws {
        let sha = String(repeating: "ab", count: 32)
        let r = try run("/bin/sh", ["scripts/render-install.sh", "1.2.3", sha, "15.0"])
        #expect(r.status == 0, "\(r.err)")
        let lines = Set(r.out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        #expect(lines.contains("VERSION='1.2.3'"))
        #expect(lines.contains("SHA256='\(sha)'"))
        #expect(lines.contains("MIN_MACOS='15.0'"))
        #expect(lines.contains("DEST='/Applications'"))
        #expect(lines.contains(
            "DMG_URL='https://github.com/Bakhtiyor7/whoisworking-releases/releases/download/v1.2.3/WhoIsWorking-1.2.3.dmg'"))
        #expect(lines.contains("PROTO='=https'"))
        #expect(lines.contains("OPEN='1'"))
        #expect(r.out.range(of: "@[A-Z0-9_]+@", options: .regularExpression) == nil)
        #expect(r.out.hasPrefix("#!/bin/sh\n"))
    }

    @Test func theRendererRefusesValuesItCannotQuote() throws {
        let sha = String(repeating: "ab", count: 32)
        let renderer = "scripts/render-install.sh"
        // Not a version, not a SHA-256, not a macOS version.
        #expect(try run("/bin/sh", [renderer, "1.2", sha, "15.0"]).status != 0)
        #expect(try run("/bin/sh", [renderer, "1.2.3", "abc", "15.0"]).status != 0)
        #expect(try run("/bin/sh", [renderer, "1.2.3", sha, "fifteen"]).status != 0)
        // A quote would end the constant early; an unknown key is a typo.
        let quoted = try run("/bin/sh", [renderer, "1.2.3", sha, "15.0", "DEST=/tmp/a'; echo owned; '"])
        #expect(quoted.status != 0)
        #expect(quoted.out.isEmpty)
        #expect(try run("/bin/sh", [renderer, "1.2.3", sha, "15.0", "WHERE=/tmp/a"]).status != 0)
        // A good line followed by a bad one must not pass as good.
        let twoLines = try run("/bin/sh", [renderer, "1.2.3", sha + "\n'; echo owned; '", "15.0"])
        #expect(twoLines.status != 0)
        #expect(twoLines.out.isEmpty)
        #expect(try run("/bin/sh", [renderer, "1.2.3\n9.9.9", sha, "15.0"]).status != 0)
        // A value that spells a placeholder would be replaced a second time.
        #expect(try run("/bin/sh", [renderer, "1.2.3", sha, "15.0", "DEST=/tmp/@OPEN@"]).status != 0)
        #expect(try run("/bin/sh", [renderer, "1.2.3", sha, "15.0", "OPEN=maybe"]).status != 0)
    }

    // MARK: Safe to run (DST-19)

    @Test func aCutOffScriptDoesNothing() throws {
        let f = try fixtures.get()
        let box = try newBox()
        let script = try box.render(version: "0.2.0", sha: try sha256(f.v020), url: "file://\(f.v020.path)")
        let lines = try String(contentsOf: script, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
        // Cut in the middle of the body, and just before the last line that starts it.
        for keep in [lines.count / 2, lines.count - 2] {
            let cut = box.root.appendingPathComponent("cut-\(keep).sh")
            try lines.prefix(keep).joined(separator: "\n").write(to: cut, atomically: true, encoding: .utf8)
            _ = try run("/bin/sh", [cut.path], environment: ["TMPDIR": box.tmp.path])
            #expect(!FileManager.default.fileExists(atPath: box.app.path))
            #expect(try box.installerEntries().isEmpty)
            #expect(try box.leftInTmp().isEmpty)
        }
    }

    @Test func environmentVariablesDoNotChangeWhatItDoes() throws {
        let f = try fixtures.get()
        let box = try newBox()
        let elsewhere = box.root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let r = try box.install(f.v020, version: "0.2.0", environment: [
            "DEST": elsewhere.path, "WHOISWORKING_INSTALL_DEST": elsewhere.path,
            "DMG_URL": "file:///nonexistent.dmg", "WHOISWORKING_INSTALL_DMG": "/nonexistent.dmg",
            "VERSION": "9.9.9", "SHA256": "0", "MIN_MACOS": "99.0", "PROTO": "=ftp", "OPEN": "1",
        ])
        #expect(r.status == 0, "\(r.all)")
        #expect(installedVersion(box.app) == "0.2.0")
        #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path).isEmpty)
    }

    // MARK: Preconditions (DST-14)

    @Test func anOlderMacOSIsRefusedBeforeAnyDownload() throws {
        let box = try newBox()
        let script = try box.render(
            version: "0.2.0", sha: String(repeating: "0", count: 64), minMacOS: "99.0",
            url: "file:///nonexistent/WhoIsWorking.dmg")
        let r = try run("/bin/sh", [script.path], environment: ["TMPDIR": box.tmp.path])
        #expect(r.status != 0)
        #expect(r.err.contains("macOS 99.0"))
        #expect(!r.all.contains("download"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: box.dest.path).isEmpty)
    }

    @Test func aForeignEntryAtTheDestinationIsRefused() throws {
        let f = try fixtures.get()
        // Another app under the same name.
        var box = try newBox()
        _ = try makeApp(in: box.dest, version: "0.1.0", id: "com.example.Other", helper: f.helper)
        var r = try box.install(f.v020, version: "0.2.0")
        #expect(r.status != 0)
        #expect(r.err.contains("com.example.Other"))
        #expect(installedVersion(box.app) == "0.1.0")
        #expect(try box.installerEntries().isEmpty)

        // A symlink under the same name: neither followed nor replaced.
        box = try newBox()
        let target = box.root.appendingPathComponent("target")
        _ = try makeApp(in: target, version: "0.1.0", helper: f.helper)
        try FileManager.default.createSymbolicLink(
            at: box.app, withDestinationURL: target.appendingPathComponent("WhoIsWorking.app"))
        r = try box.install(f.v020, version: "0.2.0")
        #expect(r.status != 0)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: box.app.path).hasSuffix("target/WhoIsWorking.app"))
        #expect(installedVersion(target.appendingPathComponent("WhoIsWorking.app")) == "0.1.0")
    }

    @Test func aNewerInstalledVersionIsNotDowngraded() throws {
        let f = try fixtures.get()
        let box = try newBox()
        _ = try makeApp(in: box.dest, version: "0.10.0", helper: f.helper)
        let r = try box.install(f.v020, version: "0.2.0")
        #expect(r.status != 0)
        #expect(r.err.contains("0.10.0"))
        #expect(installedVersion(box.app) == "0.10.0")
        #expect(try box.leftInTmp().isEmpty)

        // A version too long to compare as numbers is not treated as older.
        let huge = try newBox()
        _ = try makeApp(in: huge.dest, version: "0.99999999999999999999.0", helper: f.helper)
        let refused = try huge.install(f.v020, version: "0.2.0")
        #expect(refused.status != 0)
        #expect(installedVersion(huge.app) == "0.99999999999999999999.0")
    }

    @Test func anUnwritableDestinationPointsToTheDMG() throws {
        let f = try fixtures.get()
        let box = try newBox()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: box.dest.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box.dest.path) }
        let r = try box.install(f.v020, version: "0.2.0")
        #expect(r.status != 0)
        #expect(r.err.contains(".dmg"))
        #expect(!r.all.contains("sudo"))
        #expect(try box.leftInTmp().isEmpty)
    }

    @Test func aSecondInstallIsRefusedWhileOneIsRunning() throws {
        let f = try fixtures.get()
        let box = try newBox()
        // This test process stands in for the install that holds the lock.
        try FileManager.default.createSymbolicLink(atPath: box.lock.path, withDestinationPath: "\(getpid())")
        let r = try box.install(f.v020, version: "0.2.0")
        #expect(r.status != 0)
        #expect(r.err.contains("\(getpid())"))
        #expect(!FileManager.default.fileExists(atPath: box.app.path))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: box.lock.path) == "\(getpid())")
        #expect(try box.installerEntries() == [lockName])
    }

    @Test func twoInstallsAtOnceEndInOneGoodInstall() throws {
        let f = try fixtures.get()
        let box = try newBox()
        let script = try box.render(version: "0.2.0", sha: try sha256(f.v020), url: "file://\(f.v020.path)")
        let runs = try (0..<4).map { _ -> (Process, Pipe) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [script.path]
            p.environment = ["PATH": "/usr/bin:/bin", "TMPDIR": box.tmp.path]
            let pipe = Pipe()
            p.standardInput = FileHandle.nullDevice
            p.standardOutput = pipe
            p.standardError = pipe
            try p.run()
            return (p, pipe)
        }
        var succeeded = 0
        for (p, pipe) in runs {
            let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            if p.terminationStatus == 0 {
                succeeded += 1
            } else {
                // The only acceptable failure is being told that another install holds the lock.
                #expect(text.contains("another install is running"), "\(text)")
            }
        }
        #expect(succeeded >= 1)
        #expect(installedVersion(box.app) == "0.2.0")
        #expect(try run("/usr/bin/codesign", ["--verify", "--strict", box.app.path]).status == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: box.dest.path) == ["WhoIsWorking.app"])
        #expect(try box.leftInTmp().isEmpty)
    }

    @Test func aForeignEntryAtTheLockPathIsRefused() throws {
        let f = try fixtures.get()
        // A directory: the lock link must not be made inside it.
        var box = try newBox()
        try FileManager.default.createDirectory(at: box.lock, withIntermediateDirectories: true)
        let keep = box.lock.appendingPathComponent("keep.txt")
        try "mine".write(to: keep, atomically: true, encoding: .utf8)
        var r = try box.install(f.v020, version: "0.2.0")
        #expect(r.status != 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: box.lock.path) == ["keep.txt"])
        #expect(!FileManager.default.fileExists(atPath: box.app.path))

        // A symlink to a directory: neither followed nor removed.
        box = try newBox()
        let target = box.root.appendingPathComponent("precious")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try "mine".write(to: target.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: box.lock, withDestinationURL: target)
        r = try box.install(f.v020, version: "0.2.0")
        #expect(r.status != 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path) == ["keep.txt"])
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: box.lock.path) == target.path)
        #expect(!FileManager.default.fileExists(atPath: box.app.path))
    }

    // MARK: Download and checksum (DST-13)

    @Test func aWrongChecksumRefusesAndKeepsTheOldCopy() throws {
        let f = try fixtures.get()
        let box = try newBox()
        _ = try makeApp(in: box.dest, version: "0.1.0", helper: f.helper)
        let r = try box.install(f.v020, version: "0.2.0", sha: String(repeating: "0", count: 64))
        #expect(r.status != 0)
        #expect(r.err.contains("checksum"))
        #expect(installedVersion(box.app) == "0.1.0")
        #expect(try box.installerEntries().isEmpty)
        #expect(try box.leftInTmp().isEmpty)
    }

    @Test func aMissingDownloadIsReportedAndChangesNothing() throws {
        let box = try newBox()
        let script = try box.render(
            version: "0.2.0", sha: String(repeating: "0", count: 64), url: "file:///nonexistent/WhoIsWorking.dmg")
        let r = try run("/bin/sh", [script.path], environment: ["TMPDIR": box.tmp.path])
        #expect(r.status != 0)
        #expect(r.err.contains("download"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: box.dest.path).isEmpty)
        #expect(try box.leftInTmp().isEmpty)
    }

    @Test func noConnectionIsReportedAsNoNetwork() throws {
        let box = try newBox()
        // Nothing listens on port 1, so this fails the same way without a network.
        let script = try box.render(
            version: "0.2.0", sha: String(repeating: "0", count: 64),
            url: "https://127.0.0.1:1/WhoIsWorking.dmg", proto: "=https")
        let r = try run("/bin/sh", [script.path], environment: ["TMPDIR": box.tmp.path])
        #expect(r.status != 0)
        #expect(r.err.contains("connect"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: box.dest.path).isEmpty)
    }

    // MARK: Verify, replace, reopen (DST-12, DST-15, DST-16, DST-18)

    @Test func aFreshInstallPutsTheReleaseInPlaceAndLeavesNothingBehind() throws {
        let f = try fixtures.get()
        let box = try newBox()
        let r = try box.install(f.v020, version: "0.2.0")
        #expect(r.status == 0, "\(r.all)")
        #expect(installedVersion(box.app) == "0.2.0")
        #expect(try run("/usr/bin/codesign", ["--verify", "--strict", box.app.path]).status == 0)
        #expect(r.out.contains("0.2.0"))
        #expect(r.out.contains(box.app.lastPathComponent))
        #expect(!r.all.contains("sudo"))
        // Only the app is in the destination: no staging directory, no Applications link from the image.
        #expect(try FileManager.default.contentsOfDirectory(atPath: box.dest.path) == ["WhoIsWorking.app"])
        #expect(try box.leftInTmp().isEmpty)
        #expect(!(try run("/usr/bin/hdiutil", ["info"]).out.contains(box.root.lastPathComponent)))
    }

    @Test func installingOverAnOlderOrEqualCopyReplacesIt() throws {
        let f = try fixtures.get()
        let box = try newBox()
        #expect(try box.install(f.v010, version: "0.1.0").status == 0)
        #expect(installedVersion(box.app) == "0.1.0")
        // A file only the old copy has: proof the bundle was replaced, not merged into.
        let stale = box.app.appendingPathComponent("Contents/stale.txt")
        try "old".write(to: stale, atomically: true, encoding: .utf8)
        let update = try box.install(f.v020, version: "0.2.0")
        #expect(update.status == 0, "\(update.all)")
        #expect(installedVersion(box.app) == "0.2.0")
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        let again = try box.install(f.v020, version: "0.2.0")
        #expect(again.status == 0, "\(again.all)")
        #expect(installedVersion(box.app) == "0.2.0")
        #expect(try FileManager.default.contentsOfDirectory(atPath: box.dest.path) == ["WhoIsWorking.app"])
    }

    @Test func anAppWithAnotherBundleIdIsRefusedAndTheOldCopyKept() throws {
        let f = try fixtures.get()
        let box = try newBox()
        _ = try makeApp(in: box.dest, version: "0.1.0", helper: f.helper)
        let running = try start(box.app.appendingPathComponent("Contents/MacOS/WhoIsWorking"))
        defer { running.terminate() }
        // The image is intact and signed and its checksum matches: only the bundle id is wrong.
        let r = try box.install(f.wrongID, version: "0.2.0")
        #expect(r.status != 0)
        #expect(r.err.contains("com.example.Other"))
        #expect(installedVersion(box.app) == "0.1.0")
        // Refused before the running copy was touched.
        #expect(running.isRunning)
        #expect(try box.installerEntries().isEmpty)
        #expect(try box.leftInTmp().isEmpty)
    }

    @Test func aVersionOtherThanThePinnedOneIsRefused() throws {
        let f = try fixtures.get()
        let box = try newBox()
        // The right checksum for an image that holds 0.1.0, in a script pinned to 0.2.0.
        let r = try box.install(f.v010, version: "0.2.0")
        #expect(r.status != 0)
        #expect(r.err.contains("0.1.0"))
        #expect(!FileManager.default.fileExists(atPath: box.app.path))
        #expect(try box.installerEntries().isEmpty)
    }

    @Test func aCopyRunningFromTheDestinationIsStoppedFirst() throws {
        let f = try fixtures.get()
        let box = try newBox()
        #expect(try box.install(f.v010, version: "0.1.0").status == 0)
        let running = try start(box.app.appendingPathComponent("Contents/MacOS/WhoIsWorking"))
        defer { if running.isRunning { running.terminate() } }
        let r = try box.install(f.v020, version: "0.2.0")
        #expect(r.status == 0, "\(r.all)")
        running.waitUntilExit()
        #expect(running.terminationReason == .uncaughtSignal)
        #expect(installedVersion(box.app) == "0.2.0")
    }

    @Test func aCopyRunningElsewhereIsLeftAloneAndNamed() throws {
        let f = try fixtures.get()
        let box = try newBox()
        let other = box.root.appendingPathComponent("Elsewhere")
        let otherApp = try makeApp(in: other, version: "0.1.0", helper: f.helper)
        let running = try start(otherApp.appendingPathComponent("Contents/MacOS/WhoIsWorking"))
        defer { running.terminate() }
        // Rendered to open the app, as published: the script itself must decide not to.
        let r = try box.install(f.v020, version: "0.2.0", open: true)
        #expect(r.status == 0, "\(r.all)")
        #expect(installedVersion(box.app) == "0.2.0")
        #expect(running.isRunning)
        #expect(r.all.contains("Elsewhere/WhoIsWorking.app"))
        #expect(r.all.contains("was not opened"))
        #expect(!r.all.contains("Opening Who's Working"))
    }

    @Test func leftoversFromAKilledRunAreRecoveredFirst() throws {
        let f = try fixtures.get()
        let box = try newBox()
        // A run that died mid-swap: the previous app sits in its staging folder, the destination
        // is empty, and the lock names a pid that belongs to no live process.
        let left = box.dest.appendingPathComponent(".WhoIsWorking.install.abc123")
        _ = try makeApp(in: left.appendingPathComponent("old"), version: "0.1.0", helper: f.helper)
        try FileManager.default.createDirectory(at: left.appendingPathComponent("new"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: box.lock.path, withDestinationPath: "\(try box.deadPid(f.helper))")
        // This run fails at the checksum, so what is left is what the recovery did.
        let r = try box.install(f.v020, version: "0.2.0", sha: String(repeating: "0", count: 64))
        #expect(r.status != 0)
        #expect(installedVersion(box.app) == "0.1.0")
        #expect(try box.installerEntries().isEmpty)
        // And the next run installs normally.
        #expect(try box.install(f.v020, version: "0.2.0").status == 0)
        #expect(installedVersion(box.app) == "0.2.0")
    }

    @Test func aFolderThatOnlyLooksLikeALeftoverIsLeftAlone() throws {
        let f = try fixtures.get()
        let box = try newBox()
        // Named like a staging folder, but holding something an installer never puts there.
        let foreign = box.dest.appendingPathComponent(".WhoIsWorking.install.zzzzzz")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        try "mine".write(to: foreign.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        // Named like one, with an old/ that is a link to a folder elsewhere holding an app.
        let outside = box.root.appendingPathComponent("outside")
        let outsideApp = try makeApp(in: outside, version: "0.0.9", helper: f.helper)
        let linked = box.dest.appendingPathComponent(".WhoIsWorking.install.linked")
        try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linked.appendingPathComponent("old"), withDestinationURL: outside)

        // Fails at the checksum: nothing may have been "recovered" from either folder.
        let refused = try box.install(f.v020, version: "0.2.0", sha: String(repeating: "0", count: 64))
        #expect(refused.status != 0)
        #expect(!FileManager.default.fileExists(atPath: box.app.path))
        #expect(installedVersion(outsideApp) == "0.0.9")

        let r = try box.install(f.v020, version: "0.2.0")
        #expect(r.status == 0, "\(r.all)")
        #expect(installedVersion(box.app) == "0.2.0")
        #expect(r.all.contains(foreign.lastPathComponent))
        #expect(FileManager.default.fileExists(atPath: foreign.appendingPathComponent("keep.txt").path))
        #expect(installedVersion(outsideApp) == "0.0.9")
        #expect(try box.installerEntries() == [foreign.lastPathComponent, linked.lastPathComponent].sorted())
    }

    // MARK: Quarantine (DST-17)

    @Test func aQuarantinedCopyKeepsItsAttributeAndGetsTheOpenAnywaySteps() throws {
        let f = try fixtures.get()
        let box = try newBox()
        // Rendered to open the app, as published: the script itself must decide not to.
        let r = try box.install(f.quarantined, version: "0.2.0", open: true, environment: ["DITTONORSRC": "1"])
        #expect(r.status == 0, "\(r.all)")
        #expect(installedVersion(box.app) == "0.2.0")
        #expect(try run("/usr/bin/xattr", ["-p", "com.apple.quarantine", box.app.path]).status == 0)
        #expect(r.all.contains("Open Anyway"))
        #expect(!r.all.contains("Opening Who's Working"))
    }
}
