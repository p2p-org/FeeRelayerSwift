// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import ArgumentParser
import FeeRelayerSwift
import Foundation
import OrcaSwapSwift
import SolanaSwift

@main
enum App {
    static func main() async {
        await FeeRelayerCommand.main()
    }
}

struct FeeRelayerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A Swift command-line tool for API Gateway",
        subcommands: [CreateAccount.self, RelaySend.self]
    )
}

struct CreateAccount: AsyncParsableCommand {
    @Option(help: "Wallet")
    var wallet: String = "5bYReP8iw5UuLVS5wmnXfEfrYCKdiQ1FFAZQao8JqY7V"

    @Option(help: "To address")
    var mint: String = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

    @Option(help: "Transfer amount")
    var amount: UInt64 = 5000

    @Option(help: "Bloch hash")
    var blochHash: String?

    @Option(help: "Fee payer")
    var feePayer: String = "FG4Y3yX4AAchp1HvNZ7LfzFTewF2f6nDoMDCohTFrdpT"

    @Option(help: "Lamport per signature")
    var lamportPerSignature: UInt64 = 5000

    @Option(help: "Lamport per signature")
    var rentExemption: UInt64 = 0

    @Option(help: "Fee relayer endpoint")
    var feeRelayerEndpoint: String = "https://fee-relayer.key.app"

    @Option(help: "Fee relayer endpoint")
    var solanaEndpoint: String = "https://api.mainnet-beta.solana.com"

    @Flag(help: "cURL")
    var curl: Bool = false

    func run() async throws {
        let solana = JSONRPCAPIClient(endpoint: .init(address: solanaEndpoint, network: .mainnetBeta))
        var recentBlochHash = blochHash
        if recentBlochHash == nil {
            recentBlochHash = try await solana.getRecentBlockhash()
        }

        let from = try PublicKey(string: wallet)
        let mint = try PublicKey(string: mint)
        let to = try PublicKey.associatedTokenAddress(walletAddress: from, tokenMintAddress: mint)
        
        let transaction = Transaction(
            instructions: [
                SystemProgram.createAccountInstruction(
                    from: from,
                    toNewPubkey: to,
                    lamports: amount,
                    space: 165,
                    programId: TokenProgram.id
                )
            ],
            recentBlockhash: recentBlochHash,
            feePayer: try PublicKey(string: feePayer)
        )

        let preparedTransaction = PreparedTransaction(
            transaction: transaction,
            signers: [],
            expectedFee: .init(transaction: lamportPerSignature, accountBalances: rentExemption)
        )

        var httpClient: HTTPClient = FeeRelayerHTTPClient()
        if curl {
            httpClient = CURLHTTPClient()
        }

        let apiClient = FeeRelayerSwift.APIClient(httpClient: httpClient, baseUrlString: feeRelayerEndpoint, version: 1)
        do {
            let result = try await apiClient.sendTransaction(.signRelayTransaction(.init(preparedTransaction: preparedTransaction)))
            print(result)
        } catch is CURLHTTPClient.Error {
            return
        } catch {
            print(error)
        }
    }
}

struct RelaySend: AsyncParsableCommand {
    @Option(help: "Source address")
    var from: String = "5bYReP8iw5UuLVS5wmnXfEfrYCKdiQ1FFAZQao8JqY7V"

    @Option(help: "Destination address")
    var to: String = "9zRnk58ydEKxQ4BKyETG8uQQecppcxMvQaJWLkjocvPm"

    @Option(help: "Transfer amount")
    var amount: UInt64 = 5000

    @Option(help: "Bloch hash")
    var blochHash: String?

    @Option(help: "Fee payer")
    var feePayer: String = "FG4Y3yX4AAchp1HvNZ7LfzFTewF2f6nDoMDCohTFrdpT"

    @Option(help: "Lamport per signature")
    var lamportPerSignature: UInt64 = 5000

    @Option(help: "Lamport per signature")
    var rentExemption: UInt64 = 0

    @Option(help: "Fee relayer endpoint")
    var feeRelayerEndpoint: String = "https://fee-relayer.key.app"

    @Option(help: "Fee relayer endpoint")
    var solanaEndpoint: String = "https://api.mainnet-beta.solana.com"

    @Flag(help: "cURL")
    var curl: Bool = false

    func run() async throws {
        let solana = JSONRPCAPIClient(endpoint: .init(address: solanaEndpoint, network: .mainnetBeta))
        var recentBlochHash = blochHash
        if recentBlochHash == nil {
            recentBlochHash = try await solana.getRecentBlockhash()
        }

        let transaction = Transaction(
            instructions: [
                SystemProgram.transferInstruction(
                    from: try PublicKey(string: from),
                    to: try PublicKey(string: from),
                    lamports: amount
                ),
            ],
            recentBlockhash: recentBlochHash,
            feePayer: try PublicKey(string: feePayer)
        )

        let preparedTransaction = PreparedTransaction(
            transaction: transaction,
            signers: [],
            expectedFee: .init(transaction: lamportPerSignature, accountBalances: rentExemption)
        )

        var httpClient: HTTPClient = FeeRelayerHTTPClient()
        if curl {
            httpClient = CURLHTTPClient()
        }

        let apiClient = FeeRelayerSwift.APIClient(httpClient: httpClient, baseUrlString: feeRelayerEndpoint, version: 1)
        do {
            let result = try await apiClient.sendTransaction(.signRelayTransaction(.init(preparedTransaction: preparedTransaction)))
            print(result)
        } catch is CURLHTTPClient.Error {
            return
        } catch {
            print(error)
        }
    }
}

class CURLHTTPClient: HTTPClient {
    enum Error: Swift.Error {
        case stop
    }

    var networkManager: FeeRelayerSwift.NetworkManager = URLSession.shared

    func sendRequest<T>(request: URLRequest, decoder _: JSONDecoder) async throws -> T where T: Decodable {
        print(request.cURL())
        throw Error.stop
    }
}
