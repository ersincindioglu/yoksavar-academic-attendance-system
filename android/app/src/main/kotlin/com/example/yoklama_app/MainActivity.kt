package com.example.yoklama_app

import android.Manifest
import android.app.PendingIntent
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.os.Build
import android.os.Bundle
import android.os.ParcelUuid
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterFragmentActivity() {

    // ── NFC ──
    private val NFC_CHANNEL = "yoklama/nfc"
    private var nfcAdapter: NfcAdapter? = null
    private var pendingIntent: PendingIntent? = null
    @Volatile
    private var lastUidHex: String? = null

    // ── BLE Advertising ──
    private val BLE_CHANNEL = "yoklama/ble"
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bleAdvertiser: BluetoothLeAdvertiser? = null
    private var isAdvertising = false
    private val PERMISSION_REQUEST_CODE = 9999

    // Sabit Service UUID - öğrenci bu UUID'yi arıyor
    private val SERVICE_UUID = ParcelUuid(UUID.fromString("0000ABCD-0000-1000-8000-00805F9B34FB"))

    // Manufacturer ID (0xFF01 = custom/test)
    private val MANUFACTURER_ID = 0xFF01

    @Volatile
    private var permissionResult: MethodChannel.Result? = null

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            super.onStartSuccess(settingsInEffect)
            isAdvertising = true
            Log.d("YOKLAMA_BLE", "✅ BLE advertising başarıyla başladı!")
        }

        override fun onStartFailure(errorCode: Int) {
            super.onStartFailure(errorCode)
            isAdvertising = false
            val reason = when (errorCode) {
                ADVERTISE_FAILED_DATA_TOO_LARGE -> "Veri çok büyük"
                ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Çok fazla yayıncı"
                ADVERTISE_FAILED_ALREADY_STARTED -> "Zaten yayında"
                ADVERTISE_FAILED_INTERNAL_ERROR -> "Dahili hata"
                ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "Cihaz BLE yayınını desteklemiyor"
                else -> "Bilinmeyen hata ($errorCode)"
            }
            Log.e("YOKLAMA_BLE", "❌ BLE advertising başarısız: $reason")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // NFC
        nfcAdapter = NfcAdapter.getDefaultAdapter(this)
        val intent = Intent(this, javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
        pendingIntent = PendingIntent.getActivity(this, 0, intent, flags)

        // Bluetooth
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter

        Log.d("YOKLAMA_BLE", "onCreate: BT adapter=${bluetoothAdapter != null}")
        Log.d("YOKLAMA_BLE", "onCreate: BLE advertiser destekli=${bluetoothAdapter?.bluetoothLeAdvertiser != null}")
        Log.d("YOKLAMA_BLE", "onCreate: isMultipleAdvertisementSupported=${bluetoothAdapter?.isMultipleAdvertisementSupported}")
        Log.d("YOKLAMA_NFC", "onCreate: nfcAdapter=${nfcAdapter != null}")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ══════════════════════════
        // NFC KANALI
        // ══════════════════════════
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NFC_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanUid" -> {
                        val uid = lastUidHex
                        if (uid != null) {
                            lastUidHex = null
                            result.success(uid)
                        } else {
                            result.success("")
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ══════════════════════════
        // BLE YAYIN KANALI
        // ══════════════════════════
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "requestPermissions" -> {
                        if (hasBluetoothPermissions()) {
                            result.success(true)
                        } else {
                            permissionResult = result
                            requestBluetoothPermissions()
                        }
                    }

                    "startAdvertising" -> {
                        val sessionName = call.argument<String>("name")
                        if (sessionName == null) {
                            result.error("NO_NAME", "Session adı eksik", null)
                            return@setMethodCallHandler
                        }

                        if (!hasBluetoothPermissions()) {
                            result.error("NO_PERM", "Bluetooth izinleri verilmemiş", null)
                            return@setMethodCallHandler
                        }

                        val adapter = bluetoothAdapter
                        if (adapter == null || !adapter.isEnabled) {
                            result.error("NO_BT", "Bluetooth kapalı veya desteklenmiyor", null)
                            return@setMethodCallHandler
                        }

                        try {
                            bleAdvertiser = adapter.bluetoothLeAdvertiser
                            if (bleAdvertiser == null) {
                                result.error("NO_ADV", "Bu cihaz BLE yayınını desteklemiyor", null)
                                return@setMethodCallHandler
                            }

                            // Zaten yayındaysa durdur
                            if (isAdvertising) {
                                bleAdvertiser?.stopAdvertising(advertiseCallback)
                                isAdvertising = false
                                Thread.sleep(500)
                            }

                            // Session adını byte dizisine çevir
                            val sessionBytes = sessionName.toByteArray(Charsets.UTF_8)
                            Log.d("YOKLAMA_BLE", "Session adı: $sessionName, byte uzunluğu: ${sessionBytes.size}")

                            // Yayın ayarları
                            val settings = AdvertiseSettings.Builder()
                                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                                .setConnectable(false)
                                .setTimeout(0)
                                .build()

                            // Yayın verisi: Service UUID + Manufacturer Data
                            val data = AdvertiseData.Builder()
                                .setIncludeDeviceName(false) // cihaz adına güvenme
                                .setIncludeTxPowerLevel(false)
                                .addServiceUuid(SERVICE_UUID) // sabit UUID
                                .addManufacturerData(MANUFACTURER_ID, sessionBytes) // session ID veri olarak
                                .build()

                            // Scan response: ek veri (opsiyonel)
                            val scanResponse = AdvertiseData.Builder()
                                .setIncludeDeviceName(true)
                                .setIncludeTxPowerLevel(true)
                                .build()

                            bleAdvertiser?.startAdvertising(settings, data, scanResponse, advertiseCallback)

                            // Callback'in tetiklenmesi için kısa bekleme
                            Thread.sleep(600)

                            Log.d("YOKLAMA_BLE", "startAdvertising çağrıldı: session=$sessionName, isAdv=$isAdvertising")
                            result.success(true)

                        } catch (e: SecurityException) {
                            Log.e("YOKLAMA_BLE", "SecurityException: ${e.message}")
                            result.error("SECURITY", "Bluetooth izni gerekli: ${e.message}", null)
                        } catch (e: Exception) {
                            Log.e("YOKLAMA_BLE", "Exception: ${e.message}")
                            result.error("ERROR", "BLE hatası: ${e.message}", null)
                        }
                    }

                    "stopAdvertising" -> {
                        try {
                            if (isAdvertising && bleAdvertiser != null) {
                                bleAdvertiser?.stopAdvertising(advertiseCallback)
                                isAdvertising = false
                                Log.d("YOKLAMA_BLE", "BLE yayını durduruldu")
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e("YOKLAMA_BLE", "Durdurma hatası: ${e.message}")
                            result.success(false)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ══════════════════════════
    // BLUETOOTH İZİN YÖNETİMİ
    // ══════════════════════════
    private fun hasBluetoothPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADMIN) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestBluetoothPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.BLUETOOTH_ADVERTISE,
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.ACCESS_FINE_LOCATION
                ),
                PERMISSION_REQUEST_CODE
            )
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.BLUETOOTH,
                    Manifest.permission.BLUETOOTH_ADMIN,
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                ),
                PERMISSION_REQUEST_CODE
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == PERMISSION_REQUEST_CODE) {
            val allGranted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            Log.d("YOKLAMA_BLE", "İzin sonucu: allGranted=$allGranted")
            permissionResult?.success(allGranted)
            permissionResult = null
        }
    }

    // ══════════════════════════
    // NFC BÖLÜMÜ
    // ══════════════════════════
    override fun onResume() {
        super.onResume()
        enableForegroundDispatch()
    }

    override fun onPause() {
        super.onPause()
        disableForegroundDispatch()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == NfcAdapter.ACTION_TAG_DISCOVERED ||
            intent.action == NfcAdapter.ACTION_TECH_DISCOVERED ||
            intent.action == NfcAdapter.ACTION_NDEF_DISCOVERED
        ) {
            val tag: Tag? = intent.getParcelableExtra(NfcAdapter.EXTRA_TAG)
            val idBytes = tag?.id
            if (idBytes != null) {
                lastUidHex = bytesToHex(idBytes)
                Log.d("YOKLAMA_NFC", "TAG UID=$lastUidHex")
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

    override fun onDestroy() {
        super.onDestroy()
        try {
            if (isAdvertising && bleAdvertiser != null) {
                bleAdvertiser?.stopAdvertising(advertiseCallback)
            }
        } catch (e: Exception) {
            Log.e("YOKLAMA_BLE", "onDestroy hatası: ${e.message}")
        }
    }
}