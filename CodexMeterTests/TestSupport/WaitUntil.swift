import Foundation

enum WaitTimeout: Error {
    case timedOut
}

@MainActor
func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while condition() == false {
        if clock.now >= deadline {
            throw WaitTimeout.timedOut
        }

        try await Task.sleep(for: .milliseconds(10))
    }
}
