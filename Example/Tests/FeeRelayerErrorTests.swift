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

    func testNotEnoughTokenBalanceError() throws {
        let string = "NotEnoughTokenBalance {\n    expected: 0.0009,\n    found: Some(\n        0.0008,\n    ),\n}"
        let error = feeRelayer.getError(responseString: string)
        XCTAssertEqual(error.type, .notEnoughTokenBalance)
    }

}
