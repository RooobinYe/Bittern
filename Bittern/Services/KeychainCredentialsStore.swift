//
//  KeychainCredentialsStore.swift
//  Bittern
//

import Foundation
import Combine
import Security

enum CredentialsStoreError: LocalizedError {
    case encodeFailed
    case decodeFailed
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodeFailed:
            "Could not encode SnapTrade credentials."
        case .decodeFailed:
            "Could not read saved SnapTrade credentials."
        case .keychainStatus(let status):
            "Keychain error \(status)."
        }
    }
}

final class CredentialsStore: ObservableObject {
    @Published private(set) var credentials: SnapTradeCredentials?

    private let storage = KeychainCredentialsStorage()

    init() {
        credentials = try? storage.load()
    }

    func save(_ credentials: SnapTradeCredentials) throws {
        let sanitized = credentials.sanitized
        try storage.save(sanitized)
        self.credentials = sanitized
    }

    func clear() throws {
        try storage.delete()
        credentials = nil
    }
}

private struct KeychainCredentialsStorage {
    private let service = "com.robinye.Bittern.snaptrade"
    private let account = "default"

    func load() throws -> SnapTradeCredentials? {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw CredentialsStoreError.keychainStatus(status)
        }

        guard let data = item as? Data else {
            throw CredentialsStoreError.decodeFailed
        }

        do {
            return try JSONDecoder().decode(SnapTradeCredentials.self, from: data)
        } catch {
            throw CredentialsStoreError.decodeFailed
        }
    }

    func save(_ credentials: SnapTradeCredentials) throws {
        guard let data = try? JSONEncoder().encode(credentials) else {
            throw CredentialsStoreError.encodeFailed
        }

        try delete(allowMissing: true)

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(item as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw CredentialsStoreError.keychainStatus(status)
        }
    }

    func delete() throws {
        try delete(allowMissing: true)
    }

    private func delete(allowMissing: Bool) throws {
        let status = SecItemDelete(baseQuery as CFDictionary)

        guard status == errSecSuccess || (allowMissing && status == errSecItemNotFound) else {
            throw CredentialsStoreError.keychainStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
