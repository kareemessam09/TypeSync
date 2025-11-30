package com.k9.typesync

import android.Manifest
import android.bluetooth.*
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.k9.typesync/ble"

    private val SERVICE_UUID = UUID.fromString("bf27730d-860a-4e09-889c-2d8b6a9e0fe7")
    private val CHAR_UUID = UUID.fromString("bf27730d-860a-4e09-889c-2d8b6a9e0fe8")
    private val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    private var bluetoothManager: BluetoothManager? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    
    private val registeredDevices = mutableSetOf<BluetoothDevice>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startServer" -> {
                    startBleServer()
                    result.success(null)
                }
                "sendText" -> {
                    val text = call.argument<String>("text")
                    if (text != null) {
                        sendNotification(text)
                        result.success(null)
                    } else {
                        result.error("ERROR", "Text is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startBleServer() {
        if (!hasPermissions()) {
            Log.e("BLE", "Missing permissions for BLE Server")
            return
        }

        Log.d("BLE", "Starting BLE Server...")

        bluetoothLeAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        if (bluetoothLeAdvertiser != null) {
            Log.d("BLE", "Stopping previous advertising...")
            bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
        }
        
        gattServer = bluetoothManager?.openGattServer(this, gattServerCallback) // setup GATT Server
        if (gattServer == null) {
            Log.e("BLE", "Unable to open GATT Server")
            return
        }
        
        // Create the Service
        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        
        val characteristic = BluetoothGattCharacteristic(
            CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ or 
            BluetoothGattCharacteristic.PROPERTY_WRITE or 
            BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ or 
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )



        service.addCharacteristic(characteristic)
        
        val added = gattServer?.addService(service)
        Log.d("BLE", "Service added request result: $added")
    }

    private fun startAdvertising() {
            // Start Advertising
        bluetoothLeAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        if (bluetoothLeAdvertiser == null) {
             Log.e("BLE", "Bluetooth LE Advertiser is null")
             return
        }

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false) 
            .addServiceUuid(android.os.ParcelUuid(SERVICE_UUID))
            .build()

        val scanResponse = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .build()

        bluetoothLeAdvertiser?.startAdvertising(settings, data, scanResponse, advertiseCallback)
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService?) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.d("BLE", "✅ Service successfully added to GATT Server")
                // Start advertising ONLY after service is added
                startAdvertising()
            } else {
                Log.e("BLE", "Failed to add service. Status: $status")
            }
        }

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                registeredDevices.add(device)
                Log.d("BLE", "Device Connected: ${device.address}")
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                registeredDevices.remove(device)
                Log.d("BLE", "Device Disconnected: ${device.address}")
            }
        }

        // Handle INCOMING requests (Laptop writing to Phone)
        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            if (CHAR_UUID == characteristic.uuid) {
                val message = String(value, Charsets.UTF_8)
                
                // Send to Flutter UI
                runOnUiThread {
                    val channel = MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
                    channel.invokeMethod("onTextReceived", message)
                }

                if (responseNeeded) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
                }
            }
        }
        
        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
             if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            }
        }
    }

    private fun sendNotification(message: String) {
        val characteristic = gattServer?.getService(SERVICE_UUID)?.getCharacteristic(CHAR_UUID)
        if (characteristic != null) {
            characteristic.value = message.toByteArray(Charsets.UTF_8)
            for (device in registeredDevices) {
                gattServer?.notifyCharacteristicChanged(device, characteristic, false)
            }
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            Log.d("BLE", "Advertising started successfully")
        }

        override fun onStartFailure(errorCode: Int) {
            Log.e("BLE", "Advertising failed: $errorCode")
        }
    }

    private fun hasPermissions(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED ||
                ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADVERTISE) != PackageManager.PERMISSION_GRANTED) {
                return false
            }
        }
        return true
    }
}