package com.example.yoklama_app

import android.app.PendingIntent
import android.content.Intent
import android.content.IntentFilter
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val CHANNEL = "yoklama/nfc"
    private var nfcAdapter: NfcAdapter? = null
    private var pendingIntent: PendingIntent? = null

    @Volatile
    private var lastUidHex: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        nfcAdapter = NfcAdapter.getDefaultAdapter(this)

        val intent = Intent(this, javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)

        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)

        pendingIntent = PendingIntent.getActivity(this, 0, intent, flags)

        Log.d("YOKLAMA_NFC", "onCreate: nfcAdapter=${nfcAdapter != null}")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanUid" -> {
                        val uid = lastUidHex
                        if (uid != null) {
                            lastUidHex = null
                            result.success(uid)
                        } else {
                            result.success("") // henüz okutulmadı
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onResume() {
        super.onResume()
        enableForegroundDispatch()
        Log.d("YOKLAMA_NFC", "onResume: foreground dispatch enabled")
    }

    override fun onPause() {
        super.onPause()
        disableForegroundDispatch()
        Log.d("YOKLAMA_NFC", "onPause: foreground dispatch disabled")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)

        Log.d("YOKLAMA_NFC", "onNewIntent action=${intent.action}")

        if (intent.action == NfcAdapter.ACTION_TAG_DISCOVERED ||
            intent.action == NfcAdapter.ACTION_TECH_DISCOVERED ||
            intent.action == NfcAdapter.ACTION_NDEF_DISCOVERED
        ) {
            val tag: Tag? = intent.getParcelableExtra(NfcAdapter.EXTRA_TAG)
            val idBytes = tag?.id

            if (idBytes != null) {
                lastUidHex = bytesToHex(idBytes)
                Log.d("YOKLAMA_NFC", "TAG UID=$lastUidHex")
            } else {
                Log.d("YOKLAMA_NFC", "TAG is null or idBytes is null")
            }
        }
    }

    private fun enableForegroundDispatch() {
        val adapter = nfcAdapter ?: return
        val pi = pendingIntent ?: return

        val filters = arrayOf(
            IntentFilter(NfcAdapter.ACTION_TAG_DISCOVERED),
            IntentFilter(NfcAdapter.ACTION_TECH_DISCOVERED),
            IntentFilter(NfcAdapter.ACTION_NDEF_DISCOVERED)
        )

        adapter.enableForegroundDispatch(this, pi, filters, null)
    }

    private fun disableForegroundDispatch() {
        nfcAdapter?.disableForegroundDispatch(this)
    }

    private fun bytesToHex(bytes: ByteArray): String {
        val sb = StringBuilder()
        for (b in bytes) {
            sb.append(String.format("%02X", b))
            sb.append(":")
        }
        if (sb.isNotEmpty()) sb.setLength(sb.length - 1)
        return sb.toString()
    }
}
