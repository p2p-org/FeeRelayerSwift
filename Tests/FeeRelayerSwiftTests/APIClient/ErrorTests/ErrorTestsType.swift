//import XCTest
//@testable import FeeRelayerSwift
//
//protocol ErrorTestsType: XCTestCase {}
//
//extension ErrorTestsType {
//    @discardableResult
//    func doTest(
//        string: String,
//        expectedErrorCode: Int,
//        expectedMessage: String,
//        expectedData: FeeRelayer.ErrorDetail? = nil
//    ) throws -> FeeRelayer.Error {
//        let data = string.data(using: .utf8)!
//        let error = try JSONDecoder().decode(FeeRelayer.Error.self, from: data)
//        XCTAssertEqual(error.code, expectedErrorCode)
//        XCTAssertEqual(error.message, expectedMessage)
//        if let expectedData = expectedData {
//            XCTAssertEqual(error.data, expectedData)
//        }
//        return error
//    }
//}
