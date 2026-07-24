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

        let authSession = AuthSession(accessToken: "token", accountID: "acct")
        let request = UsageService.request(for: authSession)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct")

        let service = UsageService(
            tokenProvider: MockTokenProvider(result: .success(authSession)),
            now: { Date(timeIntervalSince1970: 1_778_054_820) },
            requestPerformer: { _ in
                return (
                    Data(payload.utf8),
                    HTTPURLResponse(url: UsageService.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        let snapshot = try await service.fetchUsageSnapshot()

        #expect(snapshot.meter(id: .primary)?.remainingPercent == 64)
        #expect(snapshot.meter(id: .secondary)?.remainingPercent == 73)
        #expect(snapshot.meter(id: .credits)?.valueText == "12")
    }

    @Test
    func decodesWeeklyOnlyAndAdditionalRateLimitsWithoutReassigningWindowNames() async throws {
        let payload = """
        {
          "plan_type": "prolite",
          "rate_limit": {
            "primary_window": {
              "used_percent": 0,
              "limit_window_seconds": 604800,
              "reset_after_seconds": 604800,
              "reset_at": 1785275783
            },
            "secondary_window": null
          },
          "additional_rate_limits": [
            {
              "limit_name": "GPT-5.3-Codex-Spark",
              "metered_feature": "codex_bengalfox",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 25,
                  "limit_window_seconds": 604800,
                  "reset_after_seconds": 604800,
                  "reset_at": 1785275783
                },
                "secondary_window": {
                  "used_percent": 50,
                  "limit_window_seconds": 18000,
                  "reset_after_seconds": 9000
                }
              }
            }
          ],
          "credits": {
            "unlimited": false,
            "balance": "0",
            "has_credits": false
          }
        }
        """

        let service = UsageService(
            tokenProvider: MockTokenProvider(result: .success(AuthSession(accessToken: "token", accountID: nil))),
            requestPerformer: { _ in
                (
                    Data(payload.utf8),
                    HTTPURLResponse(url: UsageService.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        let snapshot = try await service.fetchUsageSnapshot()
        let sparkID = UsageMeterID.additional(feature: "codex_bengalfox")

        #expect(snapshot.meter(id: .primary)?.title == "Weekly limit")
        #expect(snapshot.meter(id: .primary)?.remainingPercent == 100)
        #expect(snapshot.meter(id: .secondary)?.isAvailable == false)
        #expect(snapshot.meter(id: .secondary)?.title == "Secondary window")
        #expect(snapshot.meter(id: sparkID)?.title == "GPT-5.3-Codex-Spark")
        #expect(snapshot.meter(id: sparkID)?.remainingPercent == 75)
        #expect(snapshot.additionalRateLimitMeters.count == 1)
        #expect(snapshot.meter(id: .credits)?.valueText == "0")
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
