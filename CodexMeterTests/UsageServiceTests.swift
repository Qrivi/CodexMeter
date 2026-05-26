import Foundation
import Testing
@testable import CodexMeter

@MainActor
struct UsageServiceTests {
    @Test
    func decodesSuccessfulResponseIntoSnapshot() async throws {
        let payload = """
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": 36,
              "limit_window_seconds": 18000,
              "reset_at": 1778070900
            },
            "secondary_window": {
              "used_percent": 27,
              "limit_window_seconds": 604800,
              "reset_after_seconds": 86400
            }
          },
          "credits": {
            "unlimited": false,
            "balance": "12",
            "has_credits": true
          }
        }
        """

        let service = UsageService(
            tokenProvider: MockTokenProvider(result: .success(AuthSession(accessToken: "token", accountID: "acct"))),
            now: { Date(timeIntervalSince1970: 1_778_054_820) },
            requestPerformer: { request in
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
                #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct")
                return (
                    Data(payload.utf8),
                    HTTPURLResponse(url: UsageService.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        let snapshot = try await service.fetchUsageSnapshot()

        #expect(snapshot.fiveHourSection.remainingPercent == 64)
        #expect(snapshot.weeklySection.remainingPercent == 73)
        #expect(snapshot.creditsText == "12")
    }

    @Test
    func returnsAuthErrorWhenTokenIsMissing() async {
        let service = UsageService(
            tokenProvider: MockTokenProvider(result: .failure(AuthTokenProviderError.missingToken)),
            requestPerformer: { _ in
                Issue.record("Request performer should not be called when auth fails.")
                throw URLError(.badURL)
            }
        )

        await #expect(throws: UsageServiceError.auth(.missingToken)) {
            try await service.fetchUsageSnapshot()
        }
    }

    @Test
    func returnsUnauthorizedFor401() async {
        let service = UsageService(
            tokenProvider: MockTokenProvider(result: .success(AuthSession(accessToken: "token", accountID: nil))),
            requestPerformer: { _ in
                (
                    Data(),
                    HTTPURLResponse(url: UsageService.endpoint, statusCode: 401, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        await #expect(throws: UsageServiceError.unauthorized) {
            try await service.fetchUsageSnapshot()
        }
    }

    @Test
    func returnsNetworkErrorForTransportFailure() async {
        let service = UsageService(
            tokenProvider: MockTokenProvider(result: .success(AuthSession(accessToken: "token", accountID: nil))),
            requestPerformer: { _ in
                throw URLError(.notConnectedToInternet)
            }
        )

        await #expect(throws: UsageServiceError.network(URLError(.notConnectedToInternet).localizedDescription)) {
            try await service.fetchUsageSnapshot()
        }
    }

    @Test
    func returnsDecodingErrorForInvalidJSON() async {
        let service = UsageService(
            tokenProvider: MockTokenProvider(result: .success(AuthSession(accessToken: "token", accountID: nil))),
            requestPerformer: { _ in
                (
                    Data("not-json".utf8),
                    HTTPURLResponse(url: UsageService.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        await #expect(throws: UsageServiceError.decoding) {
            try await service.fetchUsageSnapshot()
        }
    }
}
