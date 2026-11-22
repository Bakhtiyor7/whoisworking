/// Where the running app lives, so Settings only offers Open at login for a copy that will still
/// be there after a restart (DST-10).
public enum RunLocation: Equatable, Sendable {
    case installed
    /// Running straight from a mounted disk image (`/Volumes/…`).
    case diskImage
    /// Gatekeeper's App Translocation copy, a random read-only path that changes between launches.
    case translocated
    /// A bare binary (`swift run`, `.build/debug`), not inside an `.app` bundle.
    case notBundle

    public static func classify(bundlePath: String) -> RunLocation {
        guard bundlePath.hasSuffix(".app") else { return .notBundle }
        if bundlePath.contains("/AppTranslocation/") { return .translocated }
        if bundlePath.hasPrefix("/Volumes/") { return .diskImage }
        return .installed
    }
}
