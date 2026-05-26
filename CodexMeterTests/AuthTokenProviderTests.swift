import Foundation
import Testing
@testable import CodexMeter

@MainActor
struct AuthTokenProviderTests {
    @Test
    func returnsMissingFileErrorWhenAuthFileDoesNotExist() async {
        let provider = AuthTokenProvider(authFileURL: temporaryAuthFileURL())

        await #expect(throws: AuthTokenProviderError.fileMissing) {
            try await provider.currentSession()
        }
    }

    @Test
    func parsesAccessTokenAndAccountID() async throws {
        let authFileURL = temporaryAuthFileURL()
        try writeAuthJSON(
            """
            {
              "tokens": {
                "access_token": " token ",
                "account_id": " acct "
              }
            }
            """,
            to: authFileURL
        )
        let provider = AuthTokenProvider(authFileURL: authFileURL)

        let session = try await provider.currentSession()

        #expect(session.accessToken == "token")
        #expect(session.accountID == "acct")
    }

    @Test
    func dropsBlankAccountID() async throws {
        let authFileURL = temporaryAuthFileURL()
        try writeAuthJSON(
            """
            {
              "tokens": {
                "access_token": "token",
                "account_id": " "
              }
            }
            """,
            to: authFileURL
        )
        let provider = AuthTokenProvider(authFileURL: authFileURL)

        let session = try await provider.currentSession()

        #expect(session.accountID == nil)
    }

    @Test
    func returnsInvalidFormatForMalformedJSON() async throws {
        let authFileURL = temporaryAuthFileURL()
        try writeAuthJSON("not-json", to: authFileURL)
        let provider = AuthTokenProvider(authFileURL: authFileURL)

        await #expect(throws: AuthTokenProviderError.invalidFormat) {
            try await provider.currentSession()
        }
    }

    @Test
    func returnsMissingTokenForBlankToken() async throws {
        let authFileURL = temporaryAuthFileURL()
        try writeAuthJSON(
            """
            {
              "tokens": {
                "access_token": " "
              }
            }
            """,
            to: authFileURL
        )
        let provider = AuthTokenProvider(authFileURL: authFileURL)

        await #expect(throws: AuthTokenProviderError.missingToken) {
            try await provider.currentSession()
        }
    }
}

private func temporaryAuthFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
        .appendingPathExtension("json")
}

private func writeAuthJSON(_ json: String, to url: URL) throws {
    try Data(json.utf8).write(to: url)
}
