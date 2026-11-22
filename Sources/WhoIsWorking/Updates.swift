import AgentCore
import AppKit
import SwiftUI

/// The manual "Check for Updates" button (DST-03). Contacts GitHub only when the user clicks;
/// all decisions are in `UpdateCheck` (AgentCore).
@MainActor
final class UpdateChecker: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case done(UpdateStatus)
    }

    @Published private(set) var phase: Phase = .idle

    /// The running version; a debug build has no Info.plist and shows as "dev".
    let versionText: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    private var current: AppVersion { AppVersion(versionText) ?? AppVersion(major: 0, minor: 0, patch: 0) }

    /// Debug only: `WHOISWORKING_FAKE_LATEST=/path/body.json` (optional `WHOISWORKING_FAKE_STATUS`, default 200)
    /// answers the check from a file instead of the network, and runs it when Settings opens, for snapshots.
    private let fake: (status: Int?, body: Data?)? = {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["WHOISWORKING_FAKE_LATEST"] else { return nil }
        let status = env["WHOISWORKING_FAKE_STATUS"].flatMap(Int.init) ?? 200
        return (status == 0 ? nil : status, FileManager.default.contents(atPath: path))
    }()

    var isFaked: Bool { fake != nil }

    func check() {
        guard phase != .checking else { return }
        phase = .checking
        if let fake {
            phase = .done(UpdateCheck.evaluate(current: current, httpStatus: fake.status, body: fake.body))
            return
        }
        let current = current
        let userAgent = "WhoIsWorking/\(versionText)"
        Task {
            let (status, body) = await Self.fetchLatest(userAgent: userAgent)
            phase = .done(UpdateCheck.evaluate(current: current, httpStatus: status, body: body))
        }
    }

    func openDownloadPage(_ version: AppVersion) {
        NSWorkspace.shared.open(UpdateCheck.downloadPage(for: version))
    }

    /// One GET with no cookies, cache or stored credentials. Returns nil status when there was no response.
    nonisolated private static func fetchLatest(userAgent: String) async -> (Int?, Data?) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: UpdateCheck.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode, data)
        } catch {
            return (nil, nil)
        }
    }
}

/// Rows for Settings › General.
struct UpdateRows: View {
    @ObservedObject var updates: UpdateChecker

    var body: some View {
        HStack {
            Button("Check for Updates") { updates.check() }
                .disabled(updates.phase == .checking)
            if updates.phase == .checking {
                ProgressView().controlSize(.small)
            }
            Spacer()
            if case .done(.available(let version)) = updates.phase {
                Button("Download \(version.description)") { updates.openDownloadPage(version) }
            }
        }
        if let message {
            Text(message.text)
                .font(.callout)
                .foregroundStyle(message.isProblem ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text("Checks github.com only when you click. GitHub sees your IP address and this app's version.")
            .font(.caption).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var message: (text: String, isProblem: Bool)? {
        guard case .done(let status) = updates.phase else { return nil }
        switch status {
        case .available(let version):
            return ("Version \(version) is available. You have \(updates.versionText).", false)
        case .upToDate:
            return ("You're up to date (\(updates.versionText)).", false)
        case .noReleases:
            return ("No release has been published yet.", false)
        case .rateLimited:
            return ("GitHub's limit for update checks was reached. Try again in an hour.", true)
        case .failed:
            return ("Couldn't check for updates. Check your connection and try again.", true)
        }
    }
}
