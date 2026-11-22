import Foundation

/// A release version `MAJOR.MINOR.PATCH`, optionally written with a leading `v` (DST-02, DST-03).
public struct AppVersion: Comparable, Hashable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Accepts `1.2.3` and `v1.2.3`; anything else (missing or extra parts, letters, signs, spaces) is nil.
    public init?(_ text: String) {
        let body = text.hasPrefix("v") ? text.dropFirst() : Substring(text)
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 9, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let n = Int(part) else { return nil }
            numbers.append(n)
        }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
}

public enum UpdateStatus: Equatable, Sendable {
    case available(AppVersion)
    case upToDate
    /// The releases repo has no published release yet (404).
    case noReleases
    /// GitHub's unauthenticated rate limit was reached (403 or 429).
    case rateLimited
    /// Anything else: no response, another status, broken JSON or a tag that is not a version.
    case failed
}

/// The manual "Check for Updates" logic (DST-03). Pure: the app performs the request and passes the result in.
public enum UpdateCheck {
    public static let releasesRepo = "Bakhtiyor7/whoisworking-releases"

    public static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(releasesRepo)/releases/latest")!

    /// Built from constants and a checked version; no URL from the response is ever used.
    public static func downloadPage(for version: AppVersion) -> URL {
        URL(string: "https://github.com/\(releasesRepo)/releases/tag/v\(version)")!
    }

    /// `httpStatus` is nil when there was no response at all (offline, timeout).
    public static func evaluate(current: AppVersion, httpStatus: Int?, body: Data?) -> UpdateStatus {
        switch httpStatus {
        case 200?:
            guard let body,
                  let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let tag = object["tag_name"] as? String,
                  let latest = AppVersion(tag) else { return .failed }
            return latest > current ? .available(latest) : .upToDate
        case 404?: return .noReleases
        case 403?, 429?: return .rateLimited
        default: return .failed
        }
    }
}
