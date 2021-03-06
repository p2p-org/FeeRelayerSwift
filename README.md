# FeeRelayerSwift

[![CI Status](https://img.shields.io/travis/Chung Tran/FeeRelayerSwift.svg?style=flat)](https://travis-ci.org/Chung Tran/FeeRelayerSwift)
[![Version](https://img.shields.io/cocoapods/v/FeeRelayerSwift.svg?style=flat)](https://cocoapods.org/pods/FeeRelayerSwift)
[![License](https://img.shields.io/cocoapods/l/FeeRelayerSwift.svg?style=flat)](https://cocoapods.org/pods/FeeRelayerSwift)
[![Platform](https://img.shields.io/cocoapods/p/FeeRelayerSwift.svg?style=flat)](https://cocoapods.org/pods/FeeRelayerSwift)

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

## Installation

FeeRelayerSwift is available through [CocoaPods](https://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'FeeRelayerSwift', :git => 'https://github.com/p2p-org/FeeRelayerSwift.git'
```

## Tests
### RelayTests
To run relay tests, create a valid file with name `relay-tests.json` inside `Tests/Resources`, contains following content (without comments):
```json
{
    "topUp": {
        "endpoint": <String>, // Solana api endpoint
        "endpointAdditionalQuery": <String?>,
        "seedPhrase": <String>, // Solana account seed phrase
        "payingTokenMint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
        "payingTokenAddress": "mCZrAFuPfBDPUW45n5BSkasRLpPZpmqpY7vs3XSYE7x",
        "amount": 10000
    },
    "solToSPL": {
        "endpoint": <String>, // Solana api endpoint
        "endpointAdditionalQuery": <String?>,
        "seedPhrase": <String>, // Solana account seed phrase
        "fromMint": "So11111111111111111111111111111111111111112",
        "toMint": "2Kc38rfQ49DFaKHQaWbijkE7fcymUMLY5guUiUsDmFfn",
        "sourceAddress": <String>,
        "destinationAddress": <String>,
        "payingTokenMint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
        "payingTokenAddress": <String>,
        "inputAmount": 100000,
        "slippage": 0.2,
        "comment": "Swap 0.0001 SOL to KURO paid with USDC"
    },
    "splToSOL": {
        "endpoint": <String>, // Solana api endpoint
        "endpointAdditionalQuery": <String?>,
        "seedPhrase": <String>, // Solana account seed phrase
        "fromMint": <String>,
        "toMint": "So11111111111111111111111111111111111111112",
        "sourceAddress": <String>,
        "destinationAddress": <String>,
        "payingTokenMint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
        "payingTokenAddress": <String>,
        "inputAmount": 10000000,
        "slippage": 0.2,
        "comment": "Swap 10 KURO to SOL paid with USDC"
    },
    "splToCreatedSpl": {
        "endpoint": <String>, // Solana api endpoint
        "endpointAdditionalQuery": <String?>,
        "seedPhrase": <String>, // Solana account seed phrase
        "fromMint": <String>, // Mint of token that you want to swap from
        "toMint": <String>, // Mint of token that you want to swap to
        "sourceAddress": <String>, // Source token address
        "destinationAddress": <String?>, // Destination token address
        "payingTokenMint": <String>, // Mint of token that you want to use to pay fee
        "payingTokenAddress": <String>, // Address of token that have enough balance to cover fee
        "inputAmount": 1000000, // Input amount in lamports
        "slippage": 0.05
    },
    "splToNonCreatedSpl": {
        "endpoint": <String>, // Solana api endpoint
        "endpointAdditionalQuery": <String?>,
        "seedPhrase": <String>, // Solana account seed phrase
        "fromMint": <String>, // Mint of token that you want to swap from
        "toMint": <String>, // Mint of token that you want to swap to
        "sourceAddress": <String>, // Source token address
        "destinationAddress": null, // Destination token address
        "payingTokenMint": <String>, // Mint of token that you want to use to pay fee
        "payingTokenAddress": <String>, // Address of token that have enough balance to cover fee
        "inputAmount": 1000000, // Input amount in lamports
        "slippage": 0.05
    },
    "usdtTransfer": { // relay_transfer_spl_token
        "endpoint": <String>, // Solana api endpoint
        "endpointAdditionalQuery": <String?>,
        "seedPhrase": <String>, // Solana account seed phrase
        "mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
        "sourceTokenAddress": "mCZrAFuPfBDPUW45n5BSkasRLpPZpmqpY7vs3XSYE7x",
        "destinationAddress": "9BDAsqBpawnEmaJnMJo8NPqyL8HrT6AdujnuFsy4m8sj",
        "inputAmount": 100,
        "payingTokenAddress": "mCZrAFuPfBDPUW45n5BSkasRLpPZpmqpY7vs3XSYE7x",
        "payingTokenMint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    },
    "usdtBackTransfer": { // relay_transfer_spl_token
        "endpoint": <String>, // Solana api endpoint
        "endpointAdditionalQuery": <String?>,
        "seedPhrase": <String>, // Solana account seed phrase
        "mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
        "sourceTokenAddress": "9BDAsqBpawnEmaJnMJo8NPqyL8HrT6AdujnuFsy4m8sj",
        "destinationAddress": "mCZrAFuPfBDPUW45n5BSkasRLpPZpmqpY7vs3XSYE7x",
        "inputAmount": 100,
        "payingTokenAddress": "9BDAsqBpawnEmaJnMJo8NPqyL8HrT6AdujnuFsy4m8sj",
        "payingTokenMint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    },
    "usdtTransferToNonCreatedToken": {
        "endpoint": <String>, // Solana api endpoint
        "endpointAdditionalQuery": <String?>,
        "seedPhrase": <String>, // Solana account seed phrase
        "mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
        "sourceTokenAddress": "9BDAsqBpawnEmaJnMJo8NPqyL8HrT6AdujnuFsy4m8sj",
        "destinationAddress": "7hTyqUwMQF24B63M4vRzjYGsJ5VBiL7WiSZJ29LQQwE8",
        "inputAmount": 100,
        "expectedFee": 10000,
        "payingTokenAddress": "9BDAsqBpawnEmaJnMJo8NPqyL8HrT6AdujnuFsy4m8sj",
        "payingTokenMint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    },
    "relaySendNativeSOL": { // relay_transaction
                "endpoint": <String>, // Solana api endpoint
        "endpointAdditionalQuery": <String?>,
        "seedPhrase": <String>, // Solana account seed phrase
        "destinationAddress": <String?>, // Destination token address
        "inputAmount": 1000000, // Input amount in lamports
        "payingTokenMint": <String>, // Mint of token that you want to use to pay fee
        "payingTokenAddress": <String>, // Address of token that have enough balance to cover fee
    }
}
```

## Author

Chung Tran, bigearsenal@gmail.com

## License

FeeRelayerSwift is available under the MIT license. See the LICENSE file for more info.
