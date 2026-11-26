import Foundation
import Testing
@testable import AgentCore

/// OSS-12. `docs/trust.md` lists what Who's Working touches on a Mac. These tests fail when the code
/// touches something the page does not list, so the page cannot fall behind the code unnoticed.

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func trustPage() throws -> String {
    try String(contentsOf: repoRoot.appendingPathComponent("docs/trust.md"), encoding: .utf8)
}

/// Every regular file under `root`, by path relative to `root`, with its contents.
private func files(under root: URL) throws -> [String: Data] {
    var found: [String: Data] = [:]
    let prefix = root.resolvingSymlinksInPath().path + "/"
    guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
        return found
    }
    for case let url as URL in walker where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
        found[String(url.resolvingSymlinksInPath().path.dropFirst(prefix.count))] = try Data(contentsOf: url)
    }
    return found
}

/// Backups carry a time stamp (`.whoisworking-backup-20261126-101500`, maybe `-2`); the page writes the pattern.
private func pattern(_ path: String) -> String {
    path.replacingOccurrences(
        of: #"\.whoisworking-backup-\d{8}-\d{6}(-\d+)?$"#, with: ".whoisworking-backup-YYYYMMDD-HHMMSS",
        options: .regularExpression)
}

/// The text of one `## ` section of the page, heading included.
private func section(_ heading: String, in page: String) -> String? {
    guard let start = page.range(of: "\n## \(heading)") else { return nil }
    let rest = page[start.upperBound...]
    let end = rest.range(of: "\n## ")?.lowerBound ?? rest.endIndex
    return String(rest[..<end])
}

@Suite("Trust page")
struct TrustPageTests {
    /// Installs and then uninstalls every agent in a temporary home, through the same command the
    /// app's CLI runs, and records every file that appeared, changed or went away.
    @Test func everyFileInstallAndUninstallTouchIsListed() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("whoisworking-trust-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        // Each agent already has a hook file, so install and uninstall both write backups.
        for target in HookTarget.all {
            let file = home.appendingPathComponent(target.defaultSettingsPath)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}\n".utf8).write(to: file)
        }
        let script = home.appendingPathComponent("Library/Application Support/WhoIsWorking/whoisworking-hook")
        let plugin = home.appendingPathComponent(".config/opencode/plugins/whoisworking.js")
        func run(_ args: [String]) {
            let code = HooksCommand.run(
                args, defaultSettings: { home.appendingPathComponent($0.defaultSettingsPath) },
                hookScript: script, defaultPlugin: plugin, output: { _ in })
            #expect(code == 0, "hooks \(args.joined(separator: " ")) failed")
        }

        var touched: Set<String> = []
        var before = try files(under: home)
        for action in ["install", "uninstall"] {
            for agent in ["claude-code", "codex", "cursor", "antigravity", "opencode"] {
                run([action, "--agent", agent])
                let after = try files(under: home)
                for path in Set(before.keys).union(after.keys) where before[path] != after[path] {
                    touched.insert(pattern(path))
                }
                before = after
            }
        }

        // Sanity: the run really wrote the script, a hook file, a backup and the plugin.
        #expect(touched.contains("Library/Application Support/WhoIsWorking/whoisworking-hook"))
        #expect(touched.contains(".codex/hooks.json.whoisworking-backup-YYYYMMDD-HHMMSS"))
        #expect(touched.contains(".config/opencode/plugins/whoisworking.js"))
        let page = try trustPage()
        for path in touched.sorted() {
            #expect(page.contains("~/\(path)"), "docs/trust.md does not list ~/\(path)")
        }
    }

    @Test func theNetworkHostIsTheOneTheUpdateCheckUses() throws {
        let network = try #require(section("The one network request", in: try trustPage()), "no network section")
        #expect(network.contains(UpdateCheck.latestReleaseAPI.absoluteString))
        let page = UpdateCheck.downloadPage(for: try #require(AppVersion("1.2.3")))
        #expect(network.contains(page.absoluteString.replacingOccurrences(of: "1.2.3", with: "X.Y.Z")))
        // No other host is named there, so a new one has to be added to the page on purpose.
        let regex = try NSRegularExpression(pattern: #"https://([A-Za-z0-9.-]+)"#)
        let hosts = Set(regex.matches(in: network, range: NSRange(network.startIndex..., in: network)).compactMap {
            Range($0.range(at: 1), in: network).map { String(network[$0]) }
        })
        #expect(hosts == [UpdateCheck.latestReleaseAPI.host!, page.host!])
    }

    /// The diagnostics table names every `WHOISWORKING_*` variable the code reads (OSS-03).
    @Test func everyDebugVariableInTheSourceIsListed() throws {
        let diagnostics = try #require(section("Diagnostics", in: try trustPage()), "no diagnostics section")
        let names = try names(matching: #"WHOISWORKING_[A-Z_]+"#)
        #expect(names.count >= 9)
        for name in names.sorted() {
            // Exactly the name: `WHOISWORKING_FAKE` must not pass because `WHOISWORKING_FAKE_LATEST=` is listed.
            #expect(diagnostics.contains("`\(name)=") || diagnostics.contains("`\(name)`"), "the diagnostics table does not list \(name)")
        }
    }

    /// Every preference key the app saves appears on the page. Keys are found where they are written as a
    /// literal (`forKey: "x"`, `…Key = "x"`, `@AppStorage("x")`); a key built at run time would slip through.
    @Test func everyPreferenceKeyInTheSourceIsListed() throws {
        let page = try trustPage()
        let keys = try names(matching: #"(?:forKey:\s*|Key\s*=\s*|@AppStorage\(\s*)"([A-Za-z0-9._-]+)""#, group: 1)
        #expect(keys.contains("logEvents"))
        for key in keys.sorted() {
            #expect(page.contains("`\(key)`"), "docs/trust.md does not list the preference \(key)")
        }
    }

    /// Matches of `pattern` (or its capture `group`) across `Sources`.
    private func names(matching pattern: String, group: Int = 0) throws -> Set<String> {
        let regex = try NSRegularExpression(pattern: pattern)
        var found: Set<String> = []
        let walker = try #require(FileManager.default.enumerator(
            at: repoRoot.appendingPathComponent("Sources"), includingPropertiesForKeys: nil))
        for case let url as URL in walker where url.pathExtension == "swift" || url.pathExtension == "js" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: group), in: text) { found.insert(String(text[range])) }
            }
        }
        return found
    }
}
