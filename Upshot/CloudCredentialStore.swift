import Foundation
import Security

struct CloudCredentials: Sendable {
    let workerURL: String
    let uploadToken: String

    var isConfigured: Bool {
        !workerURL.isEmpty && !uploadToken.isEmpty
    }
}

@Observable
final class CloudCredentialStore {
    static let shared = CloudCredentialStore()

    private let defaults = UpshotStorage.defaults
    private static let keychainService = "co.chrisyork.upshot"

    private enum Keys {
        static let uploadToken = "cloud_upload_token"
        static let workerURL = "cloudWorkerURL"
    }

    private(set) var _uploadToken: String = ""
    private(set) var _workerURL: String = ""

    var uploadToken: String {
        get { _uploadToken }
        set {
            _uploadToken = newValue
            Self.setKeychainItem(key: Keys.uploadToken, value: newValue)
        }
    }

    var workerURL: String {
        get { _workerURL }
        set {
            _workerURL = newValue
            defaults.set(newValue, forKey: Keys.workerURL)
        }
    }

    var isConfigured: Bool {
        !_workerURL.isEmpty && !_uploadToken.isEmpty
    }

    func snapshot() -> CloudCredentials {
        CloudCredentials(
            workerURL: _workerURL,
            uploadToken: _uploadToken
        )
    }

    private init() {
        if UpshotStorage.isRenderingStates { return }
        _uploadToken = Self.getKeychainItem(key: Keys.uploadToken) ?? ""
        _workerURL = defaults.string(forKey: Keys.workerURL) ?? ""

        migrateFromLegacyDefaults()

        migrateFromLegacyS3Credentials()
    }

    private func migrateFromLegacyDefaults() {
        let oldTokenKey = "cloudUploadToken"
        if let oldToken = defaults.string(forKey: oldTokenKey), !oldToken.isEmpty, _uploadToken.isEmpty {
            uploadToken = oldToken
            defaults.removeObject(forKey: oldTokenKey)
        }
    }

    private func migrateFromLegacyS3Credentials() {
        let legacyDefaultsKeys = [
            "cloud_s3_bucket",
            "cloud_s3_region",
            "cloud_s3_endpoint",
            "cloud_s3_public_url_base",
        ]
        for key in legacyDefaultsKeys {
            defaults.removeObject(forKey: key)
        }

        let legacyKeychainKeys = [
            "cloud_s3_access_key_id",
            "cloud_s3_secret_access_key",
        ]
        for key in legacyKeychainKeys {
            Self.deleteKeychainItem(key: key)
        }
    }

    private static func setKeychainItem(key: String, value: String) {
        guard !UpshotStorage.isRenderingStates else { return }
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: keychainService,
        ]

        SecItemDelete(query as CFDictionary)

        var newQuery = query
        newQuery[kSecValueData as String] = data
        SecItemAdd(newQuery as CFDictionary, nil)
    }

    private static func getKeychainItem(key: String) -> String? {
        guard !UpshotStorage.isRenderingStates else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychainItem(key: String) {
        guard !UpshotStorage.isRenderingStates else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: keychainService,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
