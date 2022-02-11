import XCTest
import FeeRelayerSwift
import RxBlocking

class APIClientTests: XCTestCase {
    
    func testGetFeeRelayerPubkey() throws {
        var feeRelayer = FeeRelayer.APIClient(version: 1)
        let result = try feeRelayer.getFeePayerPubkey().toBlocking().first()
        XCTAssertEqual(result?.isEmpty, false)
        
        feeRelayer = FeeRelayer.APIClient(version: 2)
        let result2 = try feeRelayer.getFeePayerPubkey().toBlocking().first()
        XCTAssertEqual(result2?.isEmpty, false)
        
        XCTAssertNotEqual(result, result2)
    }
    
    func testGetFreeTransactionFeeLimit() throws {
        let feeRelayer = FeeRelayer.APIClient(version: 2)
        let result = try feeRelayer.requestFreeFeeLimits(for: "GZpacnxxvtFDMg16KWSH8q2g8tM7fwJvNMkb2Df34h9N").toBlocking().first()
        XCTAssertNotNil(result)
    }
}
