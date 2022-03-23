import XCTest
@testable import FeeRelayerSwift

class ErrorTests: XCTestCase {
    func testParsePubkeyError() throws {
        try doTest(
            string: #"{"code": 0, "message": "Wrong hash format \"ABC\": failed to decode string to hash", "data": {"ParsePubkeyError": ["ABC", "Invalid"]}}"#,
            expectedErrorCode: 0,
            expectedMessage: "Wrong hash format \"ABC\": failed to decode string to hash",
            expectedData: .init(type: .parsePubkeyError, data: .init(array: ["ABC", "Invalid"]))
        )
    }
    
    func testClientError() throws {
        // Account in use
        try doTest(
            string: #"{"code": 6, "message": "Solana RPC client error: Account in use", "data": {"ClientError": ["RpcError"]}}"#,
            expectedErrorCode: 6,
            expectedMessage: "Solana RPC client error: Account in use",
            expectedData: .init(type: .clientError, data: .init(array: ["RpcError"]))
        )
        
        // insufficient funds
        let error = try doTest(
            string: ClientError.insufficientFunds,
            expectedErrorCode: 6,
            expectedMessage: "Solana RPC client error: RPC response error -32002: Transaction simulation failed: Error processing Instruction 3: custom program error: 0x1 [37 log messages]",
            expectedData: nil
        )
        
        XCTAssertEqual(error.clientError?.type, .insufficientFunds)
        XCTAssertEqual(error.clientError?.errorLog, "insufficient funds")
        
        // insufficient funds 2
        let error2 = try doTest(
            string: ClientError.insufficientFunds2,
            expectedErrorCode: 6,
            expectedMessage: "Solana RPC client error: RPC response error -32002: Transaction simulation failed: Error processing Instruction 2: custom program error: 0x1 [28 log messages]",
            expectedData: nil
        )
        
        XCTAssertEqual(error2.clientError?.type, .insufficientFunds)
        XCTAssertEqual(error2.clientError?.errorLog, "insufficient lamports 19266, need 2039280")
        
        // maximum number of instructions allowed
        let error3 = try doTest(
            string: ClientError.maxNumberOfInstructionsExceeded,
            expectedErrorCode: 6,
            expectedMessage: "Solana RPC client error: RPC response error -32002: Transaction simulation failed: Error processing Instruction 2: Program failed to complete [64 log messages]"
        )
        
        XCTAssertEqual(error3.clientError?.type, .maximumNumberOfInstructionsAllowedExceeded)
        XCTAssertEqual(error3.clientError?.errorLog, "exceeded maximum number of instructions allowed (1940) at instruction #1675")
        
        // connection closed before message completed
        let error4 = try doTest(
            string: ClientError.connectionClosedBeforeMessageCompleted,
            expectedErrorCode: 6,
            expectedMessage: "Solana RPC client error: error sending request for url (https://p2p.rpcpool.com/82313b15169cb10f3ff230febb8d): connection closed before message completed"
        )
        
        XCTAssertEqual(error4.clientError?.type, .connectionClosedBeforeMessageCompleted)
        XCTAssertEqual(error4.clientError?.errorLog, "connection closed before message completed")
    }
    
    func testTooSmallAmountError() throws {
        try doTest(
            string: #"{"code": 8, "message": "Amount is too small: minimum 10, actual 5", "data": {"TooSmallAmount": {"min": 10, "actual": 5}}}"#,
            expectedErrorCode: 8,
            expectedMessage: "Amount is too small: minimum 10, actual 5",
            expectedData: .init(type: .tooSmallAmount, data: .init(dict: ["min": 10, "actual": 5]))
        )
    }
    
    func testNotEnoughOutAmountError() throws {
        try doTest(
            string: #"{"code": 17, "message": "Not enough output amount: expected 10, actual 5", "data": {"NotEnoughOutAmount": {"expected": 10, "actual": 5}}}"#,
            expectedErrorCode: 17,
            expectedMessage: "Not enough output amount: expected 10, actual 5",
            expectedData: .init(type: .notEnoughOutAmount, data: .init(dict: ["expected": 10, "actual": 5]))
        )
    }
    
    func testUnknownSwapProgramIdError() throws {
        try doTest(
            string: #"{"code": 18, "message": "Unknown Swap program ID: ABC", "data": {"UnknownSwapProgramId": ["ABC"]}}"#,
            expectedErrorCode: 18,
            expectedMessage: "Unknown Swap program ID: ABC",
            expectedData: .init(type: .unknownSwapProgramId, data: .init(array: ["ABC"]))
        )
    }
    
    @discardableResult
    private func doTest(
        string: String,
        expectedErrorCode: Int,
        expectedMessage: String,
        expectedData: FeeRelayer.ErrorDetail? = nil
    ) throws -> FeeRelayer.Error {
        let data = string.data(using: .utf8)!
        let error = try JSONDecoder().decode(FeeRelayer.Error.self, from: data)
        XCTAssertEqual(error.code, expectedErrorCode)
        XCTAssertEqual(error.message, expectedMessage)
        if let expectedData = expectedData {
            XCTAssertEqual(error.data, expectedData)
        }
        return error
    }
}
