import Foundation

private extension Array where Element == Transaction.Signature {
    func getSignature(index: Int) throws -> String {
        guard count > index else {throw FeeRelayer.Error.invalidSignature}
        guard let data = self[index].signature else {throw FeeRelayer.Error.invalidSignature}
        return Base58.encode(data)
    }
}
