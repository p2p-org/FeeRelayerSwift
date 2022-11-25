import Foundation
import FeeRelayerSwift

class MockRelayContextManagerBase: RelayContextManager {
    func getCurrentContext() async throws -> FeeRelayerSwift.RelayContext {
        fatalError()
    }
    
    func update() async throws {
        fatalError()
    }
    
    func validate() async throws -> Bool {
        fatalError()
    }
}
