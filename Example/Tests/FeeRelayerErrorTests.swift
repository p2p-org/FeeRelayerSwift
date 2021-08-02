//
//  FeeRelayerErrorTests.swift
//  FeeRelayerSwift_Tests
//
//  Created by Chung Tran on 30/07/2021.
//  Copyright © 2021 CocoaPods. All rights reserved.
//

import XCTest
@testable import FeeRelayerSwift

class FeeRelayerErrorTests: XCTestCase {
    let feeRelayer = FeeRelayer()
    let bundle = Bundle(for: FeeRelayerErrorTests.self)

    func testNotEnoughTokenBalanceError() throws {
        let string = "NotEnoughTokenBalance {\n    expected: 0.0009,\n    found: Some(\n        0.0008,\n    ),\n}"
        let error = feeRelayer.getError(responseString: string)
        XCTAssertEqual(error.type, .notEnoughTokenBalance)
        let data = error.data as! FeeRelayer.FeeRelayerErrorData
        XCTAssertEqual(data.expected, 0.0009)
        XCTAssertEqual(data.found, 0.0008)
    }

    func testClientError() throws {
        let string = FeeRelayerClientError.insufficientFunds
        let error = feeRelayer.getError(responseString: string)
        XCTAssertEqual(error.type, .clientError)
        XCTAssertEqual(error.data as? String, "insufficient funds")
    }
}
