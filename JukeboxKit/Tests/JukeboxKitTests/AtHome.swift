// The tests' device at home (SignInFailureTests.home), wherever they run:
// the fakes' 192.168.1.10 and nas.local are on its network, so plain http
// there is home, as on the photographer's own Wi-Fi.

@testable import JukeboxKit
import Testing

struct AtHome: SuiteTrait, TestTrait, TestScoping {
    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        try await LocalNetwork.$standIn.withValue(SignInFailureTests.home, operation: function)
    }
}

extension Trait where Self == AtHome {
    static var atHome: AtHome { AtHome() }
}
