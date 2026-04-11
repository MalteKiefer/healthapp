package de.kiefer_networks.healthapp

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Backs the `healthvault.security/keystore` MethodChannel.
 *
 * Each alias corresponds to one AES-256-GCM key stored in the Android
 * Keystore with user-authentication-required and invalidated-by-new-
 * biometric-enrollment flags. StrongBox is used when the device
 * supports it.
 *
 * createBioBoundKey returns the raw AES key bytes ONCE at creation time
 * so the caller (EncryptedVault) can wrap the DEK under them; the key
 * itself stays in the keystore and never leaves again. Subsequent
 * unwrapBioKey calls surface a BiometricPrompt and, on success, derive
 * a deterministic 32-byte value from the keystore key via a GCM
 * encryption of a fixed zero plaintext — giving the caller a stable
 * 32-byte value gated by biometric auth without ever exposing the
 * keystore material directly.
 */
class KeystoreHandler(private val activity: FragmentActivity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "healthvault.security/keystore"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        // Fixed plaintext used to derive a stable 32-byte value from the
        // bio-gated keystore key. Safe because GCM with a fixed IV over
        // a fixed plaintext is still a secret dependent on the key.
        private val FIXED_PLAINTEXT = ByteArray(32) { 0 }
        private val FIXED_NONCE = ByteArray(12) { 0 }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "hasKey" -> {
                    val alias = call.argument<String>("alias") ?: run {
                        result.error("bad_args", "alias required", null); return
                    }
                    result.success(hasKey(alias))
                }
                "createBioBoundKey" -> {
                    val alias = call.argument<String>("alias") ?: run {
                        result.error("bad_args", "alias required", null); return
                    }
                    createKey(alias)
                    // Immediately derive the 32-byte value for the caller.
                    deriveValue(alias, result)
                }
                "unwrapBioKey" -> {
                    val alias = call.argument<String>("alias") ?: run {
                        result.error("bad_args", "alias required", null); return
                    }
                    deriveValue(alias, result)
                }
                "deleteKey" -> {
                    val alias = call.argument<String>("alias") ?: run {
                        result.error("bad_args", "alias required", null); return
                    }
                    deleteKey(alias)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("keystore_error", e.message, null)
        }
    }

    private fun keyStore(): KeyStore =
        KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private fun hasKey(alias: String): Boolean = keyStore().containsAlias(alias)

    private fun createKey(alias: String) {
        // Remove any previous key under the same alias.
        if (hasKey(alias)) keyStore().deleteEntry(alias)

        fun buildSpec(withStrongBox: Boolean): KeyGenParameterSpec {
            val b = KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setUserAuthenticationRequired(true)
                .setInvalidatedByBiometricEnrollment(true)
                .setRandomizedEncryptionRequired(false) // we use a fixed nonce on purpose
            if (withStrongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                b.setIsStrongBoxBacked(true)
            }
            return b.build()
        }

        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        // setIsStrongBoxBacked does not throw at builder time; the
        // StrongBoxUnavailableException surfaces from generateKey() on
        // devices without StrongBox hardware. Retry without StrongBox
        // in that case so non-StrongBox devices still get a working
        // (software/TEE-backed) keystore entry.
        try {
            gen.init(buildSpec(withStrongBox = true))
            gen.generateKey()
        } catch (e: StrongBoxUnavailableException) {
            // Device advertises API >= P but has no StrongBox hardware.
            // Fall back to software/TEE-backed keystore without StrongBox.
            gen.init(buildSpec(withStrongBox = false))
            gen.generateKey()
        } catch (e: Exception) {
            // Any other hardware/keystore failure while attempting the
            // StrongBox-backed variant — retry without StrongBox as well.
            gen.init(buildSpec(withStrongBox = false))
            gen.generateKey()
        }
    }

    private fun deleteKey(alias: String) {
        if (hasKey(alias)) keyStore().deleteEntry(alias)
    }

    /**
     * Prompts BiometricPrompt with a Cipher initialised under the
     * bio-gated key, then encrypts FIXED_PLAINTEXT with FIXED_NONCE.
     * The 32-byte ciphertext (without the tag) is returned as the
     * derived value.
     */
    private fun deriveValue(alias: String, result: MethodChannel.Result) {
        val ks = keyStore()
        if (!ks.containsAlias(alias)) {
            result.error("not_found", "key not found", null); return
        }
        val key = ks.getKey(alias, null) as SecretKey
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        try {
            cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, FIXED_NONCE))
        } catch (e: Exception) {
            result.error("keystore_error", "cipher init failed: ${e.message}", null); return
        }

        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Unlock HealthVault")
            .setSubtitle("Authenticate to access your health data")
            .setNegativeButtonText("Cancel")
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .build()

        val executor = ContextCompat.getMainExecutor(activity)
        val prompt = BiometricPrompt(activity, executor, object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(auth: BiometricPrompt.AuthenticationResult) {
                try {
                    val authCipher = auth.cryptoObject?.cipher ?: cipher
                    val ciphertext = authCipher.doFinal(FIXED_PLAINTEXT)
                    // AES-GCM output: ciphertext(32) || tag(16). Take first 32 bytes.
                    val out = ciphertext.copyOfRange(0, 32)
                    result.success(out)
                } catch (e: Exception) {
                    result.error("keystore_error", "derive failed: ${e.message}", null)
                }
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                result.error("cancelled", errString.toString(), null)
            }

            override fun onAuthenticationFailed() {
                // Not terminal — system will re-prompt. Do nothing.
            }
        })

        prompt.authenticate(promptInfo, BiometricPrompt.CryptoObject(cipher))
    }
}
