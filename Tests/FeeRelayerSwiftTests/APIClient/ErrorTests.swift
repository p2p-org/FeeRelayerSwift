import XCTest
@testable import FeeRelayerSwift

class ErrorTests: XCTestCase {
    func testParsePubkeyError() throws {
        let string = #"{"code": 0, "message": "Wrong hash format \"ABC\": failed to decode string to hash", "data": {"ParsePubkeyError": ["ABC", "Invalid"]}}"#
        let data = string.data(using: .utf8)!
        let error = try JSONDecoder().decode(FeeRelayer.Error.self, from: data)
        XCTAssertEqual(error.code, 0)
        XCTAssertEqual(error.message, "Wrong hash format \"ABC\": failed to decode string to hash")
        XCTAssertEqual(error.data, .init(type: .parsePubkeyError, data: .init(array: ["ABC", "Invalid"])))
    }
    
    func testClientError() throws {
        let string = #"{"code": 6, "message": "Solana RPC client error: Account in use", "data": {"ClientError": ["RpcError"]}}"#
        let data = string.data(using: .utf8)!
        let error = try JSONDecoder().decode(FeeRelayer.Error.self, from: data)
        XCTAssertEqual(error.code, 6)
        XCTAssertEqual(error.message, "Solana RPC client error: Account in use")
        XCTAssertEqual(error.data, .init(type: .clientError, data: .init(array: ["RpcError"])))
    }
    
    func testTooSmallAmountError() throws {
        let string = #"{"code": 8, "message": "Amount is too small: minimum 10, actual 5", "data": {"TooSmallAmount": {"min": 10, "actual": 5}}}"#
        let data = string.data(using: .utf8)!
        let error = try JSONDecoder().decode(FeeRelayer.Error.self, from: data)
        XCTAssertEqual(error.code, 8)
        XCTAssertEqual(error.message, "Amount is too small: minimum 10, actual 5")
        XCTAssertEqual(error.data, .init(type: .tooSmallAmount, data: .init(dict: ["min": 10, "actual": 5])))
    }
    
    func testNotEnoughOutAmountError() throws {
        let string = #"{"code": 17, "message": "Not enough output amount: expected 10, actual 5", "data": {"NotEnoughOutAmount": {"expected": 10, "actual": 5}}}"#
        let data = string.data(using: .utf8)!
        let error = try JSONDecoder().decode(FeeRelayer.Error.self, from: data)
        XCTAssertEqual(error.code, 17)
        XCTAssertEqual(error.message, "Not enough output amount: expected 10, actual 5")
        XCTAssertEqual(error.data, .init(type: .notEnoughOutAmount, data: .init(dict: ["expected": 10, "actual": 5])))
    }
    
    func testUnknownSwapProgramIdError() throws {
        let string = #"{"code": 18, "message": "Unknown Swap program ID: ABC", "data": {"UnknownSwapProgramId": ["ABC"]}}"#
        let data = string.data(using: .utf8)!
        let error = try JSONDecoder().decode(FeeRelayer.Error.self, from: data)
        XCTAssertEqual(error.code, 18)
        XCTAssertEqual(error.message, "Unknown Swap program ID: ABC")
        XCTAssertEqual(error.data, .init(type: .unknownSwapProgramId, data: .init(array: ["ABC"])))
    }
}
