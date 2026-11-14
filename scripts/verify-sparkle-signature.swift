import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write("usage: verify-sparkle-signature.swift <SUPublicEDKey> <edSignature> <file>\n".data(using: .utf8)!)
    exit(2)
}
guard let keyData = Data(base64Encoded: arguments[1]),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    FileHandle.standardError.write("The public key is not a base64 Ed25519 key.\n".data(using: .utf8)!)
    exit(1)
}
guard let signature = Data(base64Encoded: arguments[2]) else {
    FileHandle.standardError.write("The signature is not base64.\n".data(using: .utf8)!)
    exit(1)
}
let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[3]), options: .alwaysMapped)
if publicKey.isValidSignature(signature, for: archive) {
    print("OK: \(URL(fileURLWithPath: arguments[3]).lastPathComponent) matches SUPublicEDKey \(arguments[1])")
} else {
    FileHandle.standardError.write("The EdDSA signature does not match \(arguments[3]).\n".data(using: .utf8)!)
    exit(1)
}
