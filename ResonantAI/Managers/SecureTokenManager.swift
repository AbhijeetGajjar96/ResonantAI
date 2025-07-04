import Foundation
import Security

final class SecureTokenManager {
    private let service = "com.yourapp.token"

    func saveToken(_ token: String) {
        let data = token.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)

        print("[SecureTokenManager] Token saved successfully")
    }

    func getToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        guard status == errSecSuccess, let data = dataTypeRef as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // Example: To store your OpenAI API key at app launch, call this from your app's initialization code (e.g., in ResonantAIApp.swift):
    // SecureTokenManager().saveToken("sk-ijklmnopqrstuvwxijklmnopqrstuvwxijklmnop")
} 
