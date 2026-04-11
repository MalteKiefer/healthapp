import Foundation
import Flutter
import LocalAuthentication
import Security

final class KeystoreHandler: NSObject {

    static let channelName = "healthvault.security/keystore"

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let alias = args["alias"] as? String else {
            if call.method == "hasKey" || call.method == "createBioBoundKey"
                || call.method == "unwrapBioKey" || call.method == "deleteKey" {
                result(FlutterError(code: "bad_args", message: "alias required", details: nil))
                return
            }
            result(FlutterMethodNotImplemented)
            return
        }

        switch call.method {
        case "hasKey":
            result(hasKey(alias: alias))
        case "createBioBoundKey":
            createAndRead(alias: alias, result: result)
        case "unwrapBioKey":
            read(alias: alias, result: result)
        case "deleteKey":
            delete(alias: alias)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func service(_ alias: String) -> String {
        "de.kiefer_networks.healthapp.keystore.\(alias)"
    }

    private func hasKey(alias: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(alias),
            kSecAttrAccount as String: alias,
            kSecReturnData as String: false,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    private func createAndRead(alias: String, result: @escaping FlutterResult) {
        // Remove any previous entry.
        delete(alias: alias)

        // Generate 32 random bytes.
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes { ptr -> Int32 in
            guard let base = ptr.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, 32, base)
        }
        guard status == errSecSuccess else {
            result(FlutterError(code: "keystore_error", message: "random failed", details: nil))
            return
        }

        // Access control: biometry current set (invalidated when user adds new Face/Touch ID).
        var acError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.biometryCurrentSet],
            &acError
        ) else {
            let msg = (acError?.takeRetainedValue() as Error?)?.localizedDescription ?? "access control"
            result(FlutterError(code: "keystore_error", message: msg, details: nil))
            return
        }

        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(alias),
            kSecAttrAccount as String: alias,
            kSecValueData as String: bytes,
            kSecAttrAccessControl as String: access,
        ]

        let addStatus = SecItemAdd(attrs as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            result(FlutterError(code: "keystore_error",
                                message: "SecItemAdd failed: \(addStatus)",
                                details: nil))
            return
        }

        result(bytes)
    }

    private func read(alias: String, result: @escaping FlutterResult) {
        let context = LAContext()
        context.localizedReason = "Unlock HealthVault"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(alias),
            kSecAttrAccount as String: alias,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
            kSecUseOperationPrompt as String: "Unlock HealthVault",
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            if let data = item as? Data, data.count == 32 {
                result(data)
            } else {
                result(FlutterError(code: "keystore_error",
                                    message: "unexpected data length",
                                    details: nil))
            }
        case errSecUserCanceled, errSecAuthFailed:
            result(FlutterError(code: "cancelled",
                                message: "Biometric cancelled",
                                details: nil))
        case errSecItemNotFound:
            result(FlutterError(code: "not_found",
                                message: "key not found",
                                details: nil))
        default:
            result(FlutterError(code: "keystore_error",
                                message: "SecItemCopyMatching failed: \(status)",
                                details: nil))
        }
    }

    private func delete(alias: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(alias),
            kSecAttrAccount as String: alias,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
