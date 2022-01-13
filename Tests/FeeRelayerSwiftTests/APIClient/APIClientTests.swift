import XCTest
import FeeRelayerSwift
import RxBlocking

class APIClientTests: XCTestCase {
    let feeRelayer = FeeRelayer.APIClient()
    
    func testGetFeeRelayerPubkey() throws {
        let result = try feeRelayer.getFeePayerPubkey(version: 1).toBlocking().first()
        XCTAssertEqual(result?.isEmpty, false)
        
        let result2 = try feeRelayer.getFeePayerPubkey(version: 2).toBlocking().first()
        XCTAssertEqual(result2?.isEmpty, false)
        
        XCTAssertNotEqual(result, result2)
    }
}
