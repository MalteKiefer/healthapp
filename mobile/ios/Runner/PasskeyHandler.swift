import Foundation
import Flutter

/// Stub handler for the `healthvault.security/passkey` MethodChannel.
///
/// TODO(passkey-backend): replace with a real AuthenticationServices
/// integration (ASAuthorizationController + ASAuthorizationPlatform
/// PublicKeyCredentialProvider) once the Go API gains WebAuthn endpoints.
///
/// The current impl returns unavailable / unimplemented so the Dart side
/// can show a "coming soon" UI instead of crashing.
final class PasskeyHandler: NSObject {

    static let channelName = "healthvault.security/passkey"

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "support":
            result(false)
        case "register", "authenticate":
            result(FlutterError(
                code: "not_implemented",
                message: "Passkey backend not yet available",
                details: nil
            ))
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
