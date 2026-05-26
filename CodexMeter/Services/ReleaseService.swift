import Foundation

struct AppRelease: Equatable, Sendable {
    let version: String
    let pageURL: URL
}

protocol ReleaseChecking: Sendable {
    func latestRelease() async throws -> AppRelease
}

struct GitHubReleaseService: ReleaseChecking {
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/Qrivi/CodexMeter/releases/latest")!

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    func latestRelease() async throws -> AppRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CodexMeter", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ReleaseServiceError.invalidResponse
        }

        let release = try decoder.decode(GitHubLatestReleaseResponse.self, from: data)
        return AppRelease(
            version: release.tagName.normalizedReleaseVersion,
            pageURL: release.htmlURL
        )
    }
}

enum ReleaseServiceError: Error {
    case invalidResponse
}

private struct GitHubLatestReleaseResponse: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

extension String {
    var normalizedReleaseVersion: String {
        let trimmedVersion = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedVersion.lowercased().hasPrefix("v") else {
            return trimmedVersion
        }

        return String(trimmedVersion.dropFirst())
    }

    func isOlderReleaseVersion(than other: String) -> Bool {
        let currentParts = semanticVersionParts
        let otherParts = other.semanticVersionParts
        let maxCount = max(currentParts.count, otherParts.count)

        for index in 0..<maxCount {
            let currentPart = index < currentParts.count ? currentParts[index] : 0
            let otherPart = index < otherParts.count ? otherParts[index] : 0

            if currentPart != otherPart {
                return currentPart < otherPart
            }
        }

        return false
    }

    private var semanticVersionParts: [Int] {
        normalizedReleaseVersion
            .split { character in
                character == "." || character == "-" || character == "+"
            }
            .compactMap { Int($0) }
    }
}
