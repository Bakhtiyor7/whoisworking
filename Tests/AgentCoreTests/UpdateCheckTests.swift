import Foundation
import Testing
@testable import AgentCore

@Suite("Update check")
struct UpdateCheckTests {
    static let current = AppVersion("0.2.0")!

    static func release(_ tag: String) -> Data {
        Data(#"{"tag_name": "\#(tag)", "html_url": "https://evil.example/download", "draft": false}"#.utf8)
    }

    @Test func versionsParseWithOrWithoutV() {
        #expect(AppVersion("1.2.3") == AppVersion(major: 1, minor: 2, patch: 3))
        #expect(AppVersion("v1.2.3") == AppVersion(major: 1, minor: 2, patch: 3))
        #expect(AppVersion("0.1.0")?.description == "0.1.0")
    }

    @Test func versionsCompareNumerically() {
        #expect(AppVersion("0.10.0")! > AppVersion("0.9.0")!)
        #expect(AppVersion("1.0.0")! > AppVersion("0.99.99")!)
        #expect(AppVersion("0.1.1")! > AppVersion("0.1.0")!)
        #expect(!(AppVersion("0.1.0")! < AppVersion("v0.1.0")!))
    }

    @Test func tagsThatAreNotVersionsAreRejected() {
        for tag in ["", "v", "1.2", "1.2.3.4", "1.2.x", "V1.2.3", "1.2.3-beta", " 1.2.3", "01.2.3x", "-1.2.3", "1..3"] {
            #expect(AppVersion(tag) == nil, "\(tag) should not be a version")
        }
    }

    @Test func aNewerReleaseIsAvailable() {
        let status = UpdateCheck.evaluate(current: Self.current, httpStatus: 200, body: Self.release("v0.3.0"))
        #expect(status == .available(AppVersion("0.3.0")!))
    }

    @Test func theSameOrAnOlderReleaseIsUpToDate() {
        #expect(UpdateCheck.evaluate(current: Self.current, httpStatus: 200, body: Self.release("v0.2.0")) == .upToDate)
        #expect(UpdateCheck.evaluate(current: Self.current, httpStatus: 200, body: Self.release("0.1.9")) == .upToDate)
    }

    @Test func noPublishedReleaseIsReported() {
        let body = Data(#"{"message": "Not Found", "status": "404"}"#.utf8)
        #expect(UpdateCheck.evaluate(current: Self.current, httpStatus: 404, body: body) == .noReleases)
    }

    @Test func rateLimitsAreReported() {
        let body = Data(#"{"message": "API rate limit exceeded"}"#.utf8)
        #expect(UpdateCheck.evaluate(current: Self.current, httpStatus: 403, body: body) == .rateLimited)
        #expect(UpdateCheck.evaluate(current: Self.current, httpStatus: 429, body: body) == .rateLimited)
    }

    @Test func brokenResponsesAreFailures() {
        let c = Self.current
        #expect(UpdateCheck.evaluate(current: c, httpStatus: nil, body: nil) == .failed)  // timeout, no network
        #expect(UpdateCheck.evaluate(current: c, httpStatus: 500, body: Self.release("v9.0.0")) == .failed)
        #expect(UpdateCheck.evaluate(current: c, httpStatus: 200, body: Data("not json".utf8)) == .failed)
        #expect(UpdateCheck.evaluate(current: c, httpStatus: 200, body: Data(#"{"name": "no tag"}"#.utf8)) == .failed)
        #expect(UpdateCheck.evaluate(current: c, httpStatus: 200, body: Data(#"{"tag_name": 3}"#.utf8)) == .failed)
        #expect(UpdateCheck.evaluate(current: c, httpStatus: 200, body: Self.release("latest")) == .failed)
        #expect(UpdateCheck.evaluate(current: c, httpStatus: 200, body: nil) == .failed)
    }

    @Test func theDownloadPageIsBuiltFromTheVersion() {
        #expect(UpdateCheck.downloadPage(for: AppVersion("0.3.0")!).absoluteString
            == "https://github.com/Bakhtiyor7/whoisworking-releases/releases/tag/v0.3.0")
        #expect(UpdateCheck.latestReleaseAPI.absoluteString
            == "https://api.github.com/repos/Bakhtiyor7/whoisworking-releases/releases/latest")
    }

    @Test func aRealGitHubResponseIsRead() throws {
        let data = try Data(contentsOf: fixturesDir.appendingPathComponent("github/latest-release.json"))
        #expect(UpdateCheck.evaluate(current: AppVersion("600.0.0")!, httpStatus: 200, body: data)
            == .available(AppVersion("604.0.0")!))
        #expect(UpdateCheck.evaluate(current: AppVersion("604.0.0")!, httpStatus: 200, body: data) == .upToDate)
    }
}
