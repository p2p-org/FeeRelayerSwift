import XCTest
import FeeRelayerSwift
import RxBlocking

class FeeRelayerTests: XCTestCase {
    let feeRelayer = FeeRelayer()
    
    func testGetFeeRelayerPubkey() throws {
        let result = try feeRelayer.getFeePayerPubkey().toBlocking().first()
        XCTAssertEqual(result?.isEmpty, false)
    }
}
