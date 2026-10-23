import Foundation
import Security

/// ADB's legacy RSA/SHA-1 challenge format is dictated by Android's wire protocol.
/// Private operations stay in Security.framework; only the public key is serialized.
enum ADBIdentity {
    private static let tag = Data("com.remio.adb.identity.v1".utf8)

    static var hasSavedIdentity: Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag, kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func loadOrCreate() throws -> SecKey {
        let query: [String: Any] = [kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag, kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate, kSecReturnRef as String: true]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let result { return (result as! SecKey) }
        guard status == errSecItemNotFound else { throw PortalError.keychain }
        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]]
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else { throw PortalError.keychain }
        return key
    }

    static func sign(_ token: Data, key: SecKey) throws -> Data {
        guard token.count == 20 else { throw PortalError.incompatible }
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, .rsaSignatureDigestPKCS1v15SHA1,
                                                    token as CFData, &error) else { throw PortalError.keychain }
        return signature as Data
    }

    static func publicPayload(key: SecKey) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(key) else { throw PortalError.keychain }
        var error: Unmanaged<CFError>?
        guard let der = SecKeyCopyExternalRepresentation(publicKey, &error) else { throw PortalError.keychain }
        let blob = try androidPublicKey(der: der as Data)
        return Data((blob.base64EncodedString() + " Remio@iOS\0").utf8)
    }

    static func androidPublicKey(der: Data) throws -> Data {
        let bytes = Array(der)
        var index = 0
        func read(_ tag: UInt8) throws -> [UInt8] {
            guard index + 2 <= bytes.count, bytes[index] == tag else { throw PortalError.incompatible }
            index += 1
            var length = Int(bytes[index]); index += 1
            if length & 128 != 0 {
                let count = length & 127
                guard (1...4).contains(count), index + count <= bytes.count else { throw PortalError.incompatible }
                length = 0
                for _ in 0..<count { length = length * 256 + Int(bytes[index]); index += 1 }
            }
            guard length <= bytes.count - index else { throw PortalError.incompatible }
            if tag == 0x30 { return [] }
            defer { index += length }
            return Array(bytes[index..<index + length])
        }
        _ = try read(0x30)
        var modulus = try read(0x02)
        if modulus.first == 0 { modulus.removeFirst() }
        let exponent = try read(0x02)
        guard index == bytes.count, modulus.count == 256, modulus[0] & 128 != 0,
              modulus.last! & 1 == 1, exponent == [1, 0, 1] else { throw PortalError.incompatible }
        let little = Array(modulus.reversed())
        let n = stride(from: 0, to: 256, by: 4).map { i in
            (0..<4).reduce(UInt32(0)) { $0 | UInt32(little[i + $1]) << ($1 * 8) }
        }
        // Android's public wire key contains Montgomery constants, not private data.
        var inverse: UInt32 = 1
        for _ in 0..<5 { inverse = inverse &* (2 &- (n[0] &* inverse)) }
        var rr = Array(repeating: UInt32(0), count: 64); rr[0] = 1
        for _ in 0..<4096 {
            var carry: UInt64 = 0
            for i in 0..<64 {
                let value = UInt64(rr[i]) * 2 + carry
                rr[i] = UInt32(truncatingIfNeeded: value); carry = value >> 32
            }
            let greaterOrEqual = zip(rr.reversed(), n.reversed()).first(where: { $0.0 != $0.1 }).map { $0.0 > $0.1 } ?? true
            if carry != 0 || greaterOrEqual {
                var borrow: UInt64 = 0
                for i in 0..<64 {
                    let sub = UInt64(n[i]) + borrow
                    let current = UInt64(rr[i])
                    rr[i] = UInt32(truncatingIfNeeded: current &- sub)
                    borrow = current < sub ? 1 : 0
                }
            }
        }
        var blob = Data()
        for value in [UInt32(64), 0 &- inverse] + n + rr + [UInt32(65537)] {
            var word = value.littleEndian
            withUnsafeBytes(of: &word) { blob.append(contentsOf: $0) }
        }
        return blob
    }
}
