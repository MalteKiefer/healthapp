package de.kiefer_networks.healthapp

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Stub handler for the `healthvault.security/passkey` MethodChannel.
 *
 * TODO(passkey-backend): replace this stub with a real implementation
 * using androidx.credentials CredentialManager once the Go API gains
 * WebAuthn endpoints that can issue challenges and verify attestations.
 *
 * Expected future methods:
 *   support()     -> Bool
 *   register(...) -> ByteArray (attestation)
 *   authenticate(...) -> ByteArray (assertion)
 *
 * The current impl returns unavailable / unimplemented so the Dart side
 * can show a "coming soon" UI instead of crashing.
 */
class PasskeyHandler : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "healthvault.security/passkey"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "support" -> result.success(false)
            "register", "authenticate" -> {
                result.error(
                    "not_implemented",
                    "Passkey backend not yet available",
                    null,
                )
            }
            else -> result.notImplemented()
        }
    }
}
