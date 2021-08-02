//
//  FeeRelayerClientError.swift
//  FeeRelayerSwift_Tests
//
//  Created by Chung Tran on 02/08/2021.
//  Copyright © 2021 CocoaPods. All rights reserved.
//

import Foundation

struct FeeRelayerClientError {
    static var insufficientFunds: String {
        """
        ClientError(\n    ClientError {\n        request: Some(\n            SendTransaction,\n        ),\n        kind: RpcError(\n            RpcResponseError {\n                code: -32002,\n                message: \"Transaction simulation failed: Error processing Instruction 3: custom program error: 0x1\",\n                data: SendTransactionPreflightFailure(\n                    RpcSimulateTransactionResult {\n                        err: Some(\n                            InstructionError(\n                                3,\n                                Custom(\n                                    1,\n                                ),\n                            ),\n                        ),\n                        logs: Some(\n                            [\n                                \"Program DjVE6JNiYqPL2QXyCUUh8rNjHrbz9hXHNYt99MQ59qw1 invoke [1]\",\n                                \"Program log: Instruction: Swap\",\n                                \"Program TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA invoke [2]\",\n                                \"Program log: Instruction: Transfer\",\n                                \"Program TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA consumed 3402 of 181900 compute units\",\n                                \"Program TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA success\",\n                                \"Program TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA invoke [2]\",\n                                \"Program log: Instruction: Transfer\",\n                                \"Program TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA consumed 3402 of 175536 compute units\",\n                                \"Program TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA success\",\n                                \"Program DjVE6JNiYqPL2QXyCUUh8rNjHrbz9hXHNYt99MQ59qw1 consumed 28747 of 200000 compute units\",\n                                \"Program DjVE6JNiYqPL2QXyCUUh8rNjHrbz9hXHNYt99MQ59qw1 success\",\n                                \"Program 11111111111111111111111111111111 invoke [1]\",\n                                \"Program 11111111111111111111111111111111 success\",\n                                \"Program TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA invoke [1]\",\n                                \"Program log: Instruction: InitializeAccount\",\n                                \"Program TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA consumed 4429 of 200000 compute units\",\n                                \"Program TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA success\",\n                                \"Program DjVE6JNiYqPL2QXyCUUh8rNjHrbz9hXHNYt99MQ59qw1 invoke [1]\",\n                                \"Program log: Instruction: Swap\",\n                                \"Program TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA invoke [2]\",\n                                \"Program log: Instruction: Transfer\",\n                                \"Program log: Error: insufficient funds\",\n                                \"Program TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA consumed 2662 of 181855 compute units\",\n                                \"Program TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA failed: custom program error: 0x1\",\n                                \"Program DjVE6JNiYqPL2QXyCUUh8rNjHrbz9hXHNYt99MQ59qw1 consumed 200000 of 200000 compute units\",\n                                \"Program DjVE6JNiYqPL2QXyCUUh8rNjHrbz9hXHNYt99MQ59qw1 failed: custom program error: 0x1\",\n                            ],\n                        ),\n                        accounts: None,\n                    },\n                ),\n            },\n        ),\n    },\n)
        """
    }
}
