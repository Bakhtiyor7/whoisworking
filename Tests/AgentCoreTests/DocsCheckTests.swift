import Foundation
import Testing

/// OSS-16 and OSS-23. Runs `scripts/check-docs.sh` on a small tree that passes, then on copies of it
/// with one fault each. The script itself runs on the real repository in CI.

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private let installCommand =
    "curl --proto '=https' --tlsv1.2 -fsSL -o whoisworking-install.sh https://example.invalid/latest/download/install.sh && sh whoisworking-install.sh"

/// A tree with every file the script reads, all of them clean.
private let cleanTree: [String: String] = [
    "README.md": """
        # Who's Working

        See [what it does](docs/trust.md#the-one-network-request) and [setup](#set-up-an-agent).

        ## Set up an agent

        ```bash
        \(installCommand)
        ```

        Download `WhoIsWorking-1.2.3.dmg`. In code, `[a link](nowhere.md)` is not a link.
        A pass does not prove the code is harmless.
        """,
    "docs/trust.md": "# What Who's Working does on your Mac\n\n## The one network request\n\nBack to [the README](../README.md).\n",
    "docs/agents.md": "# Agents\n\nWho's Working 1.2.3 supports these.\n",
    "SECURITY.md": "# Security\n\nReport privately.\n",
    "docs/specs/20-install-command.md": "# 20\n\n### DST-12 Install command\n\n```bash\n\(installCommand)\n```\n",
    "docs/local/plan.md": "A working note may link [anywhere](missing.md).\n",
    "Resources/Info.plist": """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>1.2.3</string></dict></plist>
        """,
]

private struct Run {
    var status: Int32
    var output: String
}

/// Writes `files` (the clean tree with `changes` applied) to a new folder and runs the script on it.
private func check(_ changes: [String: String] = [:]) throws -> Run {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("whoisworking-docs-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    for (path, text) in cleanTree.merging(changes, uniquingKeysWith: { $1 }) {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [repoRoot.appendingPathComponent("scripts/check-docs.sh").path, root.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return Run(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
}

private func readme(replacing old: String, with new: String) -> [String: String] {
    ["README.md": cleanTree["README.md"]!.replacingOccurrences(of: old, with: new)]
}

@Suite("Docs check")
struct DocsCheckTests {
    @Test func aCleanTreePasses() throws {
        let run = try check()
        #expect(run.status == 0, "\(run.output)")
    }

    @Test func aBrokenLinkOrAnchorFails() throws {
        let file = try check(readme(replacing: "(docs/trust.md#", with: "(docs/trusts.md#"))
        #expect(file.status == 1)
        #expect(file.output.contains("README.md") && file.output.contains("docs/trusts.md"), "\(file.output)")

        let anchor = try check(readme(replacing: "(#set-up-an-agent)", with: "(#set-up)"))
        #expect(anchor.status == 1)
        #expect(anchor.output.contains("#set-up"), "\(anchor.output)")
    }

    @Test func anInstallCommandThatDiffersFromTheSpecFails() throws {
        let run = try check(readme(replacing: "-fsSL -o", with: "-sL -o"))
        #expect(run.status == 1)
        #expect(run.output.contains("DST-12"), "\(run.output)")
    }

    /// The three-step form downloads the script on its own line, then runs it (OSS-14).
    @Test func theDownloadHalfOfTheInstallCommandPasses() throws {
        let download = String(installCommand.prefix { $0 != "&" }).trimmingCharacters(in: .whitespaces)
        let run = try check(readme(replacing: "Download `WhoIsWorking", with: "```bash\n\(download)\n```\n\nDownload `WhoIsWorking"))
        #expect(run.status == 0, "\(run.output)")
    }

    @Test func aPageThatCallsTheSourcePrivateOrNamesAnOldReleaseFails() throws {
        let privateSource = try check(["docs/trust.md": cleanTree["docs/trust.md"]! + "\nThis repo stays private.\n"])
        #expect(privateSource.status == 1)
        #expect(privateSource.output.contains("private"), "\(privateSource.output)")

        let oldRelease = try check(["docs/agents.md": "# Agents\n\nWho's Working 1.2.2 supports these.\n"])
        #expect(oldRelease.status == 1)
        #expect(oldRelease.output.contains("1.2.2"), "\(oldRelease.output)")

        let oldDownload = try check(readme(replacing: "WhoIsWorking-1.2.3.dmg", with: "WhoIsWorking-1.0.0.dmg"))
        #expect(oldDownload.status == 1)
    }

    @Test func aRuledOutPhraseFailsAndItsDenialPasses() throws {
        for claim in [
            "Who's Working is safe because it is open source.",
            "The app was checked by Apple.",
            "A pass proves the code is harmless.",
        ] {
            let run = try check(["SECURITY.md": "# Security\n\n\(claim)\n"])
            #expect(run.status == 1, "not refused: \(claim)")
        }
        // The clean README says "does not prove the code is harmless", which is allowed.
        #expect(try check().status == 0)
    }

    @Test func aPlaceholderLeftForPublicationFails() throws {
        let run = try check(["SECURITY.md": "# Security\n\nWrite to TO-BE-DECIDED.\n"])
        #expect(run.status == 1)
        #expect(run.output.contains("TO-BE-DECIDED"), "\(run.output)")
    }
}
