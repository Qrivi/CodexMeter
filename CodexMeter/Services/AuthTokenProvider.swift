import Foundation

struct AuthTokenProvider: TokenProviding {
    private let fileManager: FileManager
    private let authFileURL: URL

    init(
        fileManager: FileManager = .default,
        authFileURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.authFileURL = authFileURL ?? fileManager.homeDirectoryForCurrentUser
            .appending(path: ".codex")
            .appending(path: "auth.json")
    }

    func currentSession() async throws -> AuthSession {
        guard fileManager.fileExists(atPath: authFileURL.path) else {
            throw AuthTokenProviderError.fileMissing
        }

        let data: Data

        do {
            data = try Data(contentsOf: authFileURL)
        } catch {
            throw AuthTokenProviderError.unreadableFile
        }

        let payload: Any

        do {
            payload = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AuthTokenProviderError.invalidFormat
        }

        guard let root = payload as? [String: Any] else {
            throw AuthTokenProviderError.invalidFormat
        }

        guard let tokens = root["tokens"] as? [String: Any] else {
            throw AuthTokenProviderError.invalidFormat
        }

        let accessToken = (tokens["access_token"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let accessToken, accessToken.isEmpty == false else {
            throw AuthTokenProviderError.missingToken
        }

        let accountID = (tokens["account_id"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return AuthSession(
            accessToken: accessToken,
            accountID: accountID?.isEmpty == true ? nil : accountID
        )
    }
}
