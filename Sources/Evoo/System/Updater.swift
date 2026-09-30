import AppKit
import CryptoKit
import os

/// Keeps Evoo up to date from GitHub Releases: every push to `main` publishes a numbered build
/// (see .github/workflows/release.yml); this compares it with the running build, and "Install Update"
/// downloads it, verifies its SHA-256, swaps the app bundle, and relaunches.
///
/// No Apple Developer ID needed: files downloaded by the app itself aren't quarantined, so Gatekeeper
/// doesn't block the new version, and macOS keeps permissions because the code requirement is pinned
/// to the bundle ID (scripts/bundle.sh).
@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(build: Int)
        case installing(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let log = Logger(subsystem: "app.evoo", category: "updates")
    private var latest: (build: Int, zip: URL, sha: URL)?
    private var timer: Timer?

    /// "owner/repo", stamped into Info.plist by CI. Nil in local builds (updates disabled).
    let repository = Bundle.main.object(forInfoDictionaryKey: "EvooRepository") as? String
    let currentBuild = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0

    var isEnabled: Bool { repository != nil }

    func start() {
        guard isEnabled else { return }
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }

    func check() {
        guard let repository, state != .checking, !isInstalling else { return }
        state = .checking
        Task {
            do {
                let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
                var request = URLRequest(url: url)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, _) = try await URLSession.shared.data(for: request)
                let release = try JSONDecoder().decode(Release.self, from: data)
                guard let build = Int(release.tag_name.replacingOccurrences(of: "build-", with: "")),
                      // Updates download their own copy, so new downloads of Evoo.zip can be counted on their own.
                      let zip = (release.assets.first(where: { $0.name == "Evoo-update.zip" })
                          ?? release.assets.first(where: { $0.name == "Evoo.zip" }))?.browser_download_url,
                      let sha = (release.assets.first(where: { $0.name == "Evoo-update.zip.sha256" })
                          ?? release.assets.first(where: { $0.name == "Evoo.zip.sha256" }))?.browser_download_url
                else { throw UpdateError.malformedRelease }
                latest = (build, zip, sha)
                state = build > currentBuild ? .available(build: build) : .upToDate
            } catch {
                log.error("update check failed: \(error.localizedDescription, privacy: .public)")
                state = .failed("Couldn't check for updates")
            }
        }
    }

    private var isInstalling: Bool {
        if case .installing = state { true } else { false }
    }

    func install() {
        guard let latest, !isInstalling else { return }
        state = .installing("Downloading build \(latest.build)…")
        Task {
            do {
                let fm = FileManager.default
                let work = fm.temporaryDirectory.appendingPathComponent("evoo-update-\(latest.build)")
                try? fm.removeItem(at: work)
                try fm.createDirectory(at: work, withIntermediateDirectories: true)

                let (zipTemp, _) = try await URLSession.shared.download(from: latest.zip)
                let zip = work.appendingPathComponent("Evoo.zip")
                try fm.moveItem(at: zipTemp, to: zip)
                let (shaData, _) = try await URLSession.shared.data(from: latest.sha)
                let expected = String(decoding: shaData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                let actual = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
                guard actual == expected else { throw UpdateError.checksumMismatch }

                state = .installing("Installing…")
                try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
                let newApp = work.appendingPathComponent("Evoo.app")
                guard fm.fileExists(atPath: newApp.path) else { throw UpdateError.malformedRelease }
                relaunch(replacing: Bundle.main.bundleURL, with: newApp)
            } catch {
                log.error("update failed: \(error.localizedDescription, privacy: .public)")
                state = .failed("Update failed: \(error.localizedDescription)")
            }
        }
    }

    /// Hands off to a tiny shell script that waits for Evoo to quit, swaps the bundle, and reopens it.
    private func relaunch(replacing current: URL, with newApp: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(current.path)"
        mv "\(newApp.path)" "\(current.path)"
        open "\(current.path)"
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError.unpackFailed }
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }

        let tag_name: String
        let assets: [Asset]
    }

    enum UpdateError: LocalizedError {
        case malformedRelease, checksumMismatch, unpackFailed
        var errorDescription: String? {
            switch self {
            case .malformedRelease: "the release is missing files"
            case .checksumMismatch: "the download didn't verify"
            case .unpackFailed: "couldn't unpack the download"
            }
        }
    }
}
