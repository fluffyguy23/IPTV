package com.iptvxtreme.player.core

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.iptvxtreme.player.IPTVApp
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Stores profile passwords encrypted with AES-256-GCM using a key that lives in
 * the Android Keystore (hardware-backed where available). The key never leaves
 * the Keystore and cannot be exported, so the ciphertext on disk is useless on
 * any other device or after uninstall. Nothing secret is ever logged.
 */
object CredentialStore {
    private const val KEY_ALIAS = "iptvxtreme.credentials.v1"
    private const val PREFS = "credentials.v1"
    private const val TAG_BITS = 128

    private val prefs get() = IPTVApp.instance.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return gen.generateKey()
    }

    fun set(password: String, profileID: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.iv + cipher.doFinal(password.toByteArray(Charsets.UTF_8))
        prefs.edit().putString(profileID, Base64.encodeToString(sealed, Base64.NO_WRAP)).apply()
    }

    fun password(profileID: String): String? {
        val stored = prefs.getString(profileID, null) ?: return null
        return try {
            val sealed = Base64.decode(stored, Base64.NO_WRAP)
            val iv = sealed.copyOfRange(0, 12)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, iv))
            String(cipher.doFinal(sealed, 12, sealed.size - 12), Charsets.UTF_8)
        } catch (e: Exception) {
            // Key was invalidated (e.g. restored onto another device): treat as missing.
            Log.error("Stored credential could not be decrypted; re-entry required")
            null
        }
    }

    fun delete(profileID: String) {
        prefs.edit().remove(profileID).apply()
    }
}
