import Foundation

/// A newer release of WinterVoice on GitHub, ready to present to the user.
struct AvailableUpdate: Equatable, Sendable {
    /// Normalized version without the tag's leading "v", e.g. "0.4.0".
    let version: String
    /// The "What's new" bullet lines from the release notes, markdown intact.
    let highlights: [String]
    /// Direct link to the release's `.dmg` asset, when the release has one.
    let downloadURL: URL?
    /// The release page on GitHub.
    let releaseURL: URL
}

@MainActor
protocol UpdateChecking: AnyObject {
    /// Returns the newer release, or nil when the app is up to date.
    func fetchAvailableUpdate() async throws -> AvailableUpdate?
}

/// Checks the project's GitHub Releases feed — the same place the README
/// sends users — so a release becomes discoverable in-app the moment it is
/// published, with no separate update feed to maintain.
@MainActor
final class GitHubUpdateChecker: UpdateChecking {
    static let repository = "winterzxzz/winter_voice"

    private let currentVersion: String
    private let loadData: (URLRequest) async throws -> Data

    init(
        currentVersion: String? = nil,
        loadData: ((URLRequest) async throws -> Data)? = nil
    ) {
        self.currentVersion = currentVersion
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0"
        self.loadData = loadData ?? { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            return data
        }
    }

    func fetchAvailableUpdate() async throws -> AvailableUpdate? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub's API rejects requests without a User-Agent.
        request.setValue("WinterVoice/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let data = try await loadData(request)
        let release = try JSONDecoder().decode(Release.self, from: data)
        return Self.availableUpdate(from: release, currentVersion: currentVersion)
    }

    // Static, injected-input core so tests can drive it without networking.
    static func availableUpdate(from release: Release, currentVersion: String) -> AvailableUpdate? {
        let remoteVersion = normalize(release.tagName)
        guard isVersion(remoteVersion, newerThan: normalize(currentVersion)),
              let releaseURL = URL(string: release.htmlURL) else { return nil }
        let dmg = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        return AvailableUpdate(
            version: remoteVersion,
            highlights: highlights(fromReleaseNotes: release.body ?? ""),
            downloadURL: dmg.flatMap { URL(string: $0.browserDownloadURL) },
            releaseURL: releaseURL
        )
    }

    /// The bullet lines of the "What's new" section. Install instructions and
    /// anything after the next heading are the release page's business, not
    /// the in-app prompt's. A notes body without the expected heading falls
    /// back to every top-level bullet in the document.
    static func highlights(fromReleaseNotes body: String) -> [String] {
        let lines = body.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var collected: [String] = []
        var inWhatsNew = false
        var sawWhatsNewHeading = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                inWhatsNew = trimmed.lowercased().contains("what's new")
                if inWhatsNew { sawWhatsNewHeading = true }
                continue
            }
            guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { continue }
            if inWhatsNew || !sawWhatsNewHeading {
                collected.append(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }
        }
        return collected
    }

    static func normalize(_ version: String) -> String {
        var normalized = version.trimmingCharacters(in: .whitespaces)
        if normalized.lowercased().hasPrefix("v") { normalized.removeFirst() }
        return normalized
    }

    /// Numeric dotted comparison; missing components count as 0, non-numeric
    /// components as 0 ("0.4.0-beta" ranks as 0.4.0).
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        func components(_ version: String) -> [Int] {
            version.split(separator: "-").first.map(String.init).map {
                $0.split(separator: ".").map { Int($0) ?? 0 }
            } ?? []
        }
        let lhs = components(candidate)
        let rhs = components(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    struct Release: Decodable {
        let tagName: String
        let htmlURL: String
        let body: String?
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
            case assets
        }
    }
}
