import Foundation

struct UsageService: UsageFetching {
    static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    private let tokenProvider: TokenProviding
    private let requestPerformer: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let now: @Sendable () -> Date

    init(
        tokenProvider: TokenProviding,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = Date.init,
        requestPerformer: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil
    ) {
        self.tokenProvider = tokenProvider
        self.now = now
        self.requestPerformer = requestPerformer ?? { request in
            try await session.data(for: request)
        }
    }

    func fetchUsageSnapshot() async throws -> UsageSnapshot {
        let authSession: AuthSession

        do {
            authSession = try await tokenProvider.currentSession()
        } catch let error as AuthTokenProviderError {
            throw UsageServiceError.auth(error)
        } catch {
            throw UsageServiceError.auth(.unreadableFile)
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let accountID = authSession.accountID, accountID.isEmpty == false {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await requestPerformer(request)
        } catch let error as URLError {
            throw UsageServiceError.network(error.localizedDescription)
        } catch {
            throw UsageServiceError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw UsageServiceError.unauthorized
        default:
            throw UsageServiceError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let usageResponse: UsageResponse

        do {
            usageResponse = try decoder.decode(UsageResponse.self, from: data)
        } catch {
            throw UsageServiceError.decoding
        }

        return UsageFormatting.snapshot(from: usageResponse, now: now())
    }
}
