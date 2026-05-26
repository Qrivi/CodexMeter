import Foundation

enum AuthTokenProviderError: LocalizedError, Equatable, Sendable {
    case fileMissing
    case unreadableFile
    case invalidFormat
    case missingToken

    var errorDescription: String? {
        switch self {
        case .fileMissing:
            "Auth token file not found."
        case .unreadableFile:
            "Auth token file could not be read."
        case .invalidFormat:
            "Auth token file is invalid."
        case .missingToken:
            "Auth token is missing."
        }
    }
}

enum UsageServiceError: LocalizedError, Equatable, Sendable {
    case auth(AuthTokenProviderError)
    case unauthorized
    case network(String)
    case invalidResponse
    case decoding

    var errorDescription: String? {
        switch self {
        case .auth:
            "Authentication failed."
        case .unauthorized:
            "Usage request was unauthorized."
        case let .network(message):
            message
        case .invalidResponse:
            "The usage service returned an invalid response."
        case .decoding:
            "The usage response could not be decoded."
        }
    }

    var userFacingMessage: String {
        switch self {
        case .auth, .unauthorized:
            "Auth token unavailable. Open Codex to refresh it."
        case let .network(message):
            message
        case .invalidResponse:
            "Usage data is temporarily unavailable."
        case .decoding:
            "Usage data could not be read."
        }
    }
}
