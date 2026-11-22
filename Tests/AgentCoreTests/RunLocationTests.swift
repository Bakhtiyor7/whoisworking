import Testing
@testable import AgentCore

@Suite("Run location")
struct RunLocationTests {
    @Test func anAppInApplicationsIsInstalled() {
        #expect(RunLocation.classify(bundlePath: "/Applications/WhoIsWorking.app") == .installed)
        #expect(RunLocation.classify(bundlePath: "/Users/me/Applications/WhoIsWorking.app") == .installed)
        // A local build counts as installed: Open at login then points at it, as before.
        #expect(RunLocation.classify(bundlePath: "/Users/me/dev/perch/build/WhoIsWorking.app") == .installed)
    }

    @Test func anAppOnADiskImageIsNotInstalled() {
        #expect(RunLocation.classify(bundlePath: "/Volumes/WhoIsWorking/WhoIsWorking.app") == .diskImage)
    }

    @Test func aTranslocatedAppIsNotInstalled() {
        let path = "/private/var/folders/xy/abc/T/AppTranslocation/1F2E3D4C/d/WhoIsWorking.app"
        #expect(RunLocation.classify(bundlePath: path) == .translocated)
    }

    @Test func aBareBinaryIsNotABundle() {
        #expect(RunLocation.classify(bundlePath: "/Users/me/dev/perch/.build/debug") == .notBundle)
        #expect(RunLocation.classify(bundlePath: "/Applications/WhoIsWorking.app/Contents/MacOS") == .notBundle)
    }
}
