import XCTest
import FeeRelayerSwift
import RxBlocking

class FeeRelayerAPIClientTests: XCTestCase {
    let feeRelayer = FeeRelayer.APIClient()
    
    func testGetFeeRelayerPubkey() throws {
        let result = try feeRelayer.getFeePayerPubkey().toBlocking().first()
        XCTAssertEqual(result?.isEmpty, false)
    }
}
