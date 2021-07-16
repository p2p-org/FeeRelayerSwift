import XCTest
import FeeRelayerSwift
import RxBlocking

class FeeRelayerTests: XCTestCase {
    let feeRelayer = FeeRelayer(errorType: TestError.self)
    
    func testGetFeeRelayerPubkey() throws {
        let result = try feeRelayer.getFeePayerPubkey().toBlocking().first()
        XCTAssertEqual(result?.isEmpty, false)
    }
    
}

enum TestError: FeeRelayerError {
    case invalidResponse(code: Int, message: String)
    
    static func createInvalidResponseError(code: Int, message: String) -> TestError {
        .invalidResponse(code: code, message: message)
    }
}
