import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class LinuxBluetoothService {
  final String serviceUuid = 'bf27730d-860a-4e09-889c-2d8b6a9e0fe7';
  final String charUuid = 'bf27730d-860a-4e09-889c-2d8b6a9e0fe8';

  BluetoothCharacteristic? _targetCharacteristic;

  final _messageController = StreamController<String>.broadcast();
  Stream<String> get messageStream => _messageController.stream;

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  final _scanResultsController = StreamController<List<ScanResult>>.broadcast();
  Stream<List<ScanResult>> get scanResultsStream =>
      _scanResultsController.stream;

  Future<void> startScan() async {
    if (await FlutterBluePlus.isSupported == false) {
      _statusController.add("Bluetooth not supported");
      return;
    }

    _statusController.add("Scanning...");

    _scanResultsController.add([]);

    // Listen for scan results
    FlutterBluePlus.scanResults.listen((results) {
      final filtered = results
          .where(
            (r) =>
                r.device.platformName.isNotEmpty ||
                r.advertisementData.serviceUuids.any(
                  (uuid) => uuid.toString() == serviceUuid,
                ),
          )
          .toList();

      _scanResultsController.add(filtered);
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    await _connectToDevice(device);
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _statusController.add("Connecting to ${device.platformName}...");
    print("Connecting to: ${device.platformName} (${device.remoteId})");

    await FlutterBluePlus.stopScan();

    try {
      if (device.isConnected == false) {
        await device
            .connect(autoConnect: false)
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                throw TimeoutException(
                  "Connection timed out. Check if device is in range or needs pairing.",
                );
              },
            );
      }

      try {
        var bondState = await device.bondState.first;
        if (bondState != BluetoothBondState.bonded) {
          _statusController.add("Attempting to pair...");
          try {
            await device.createBond();
            // Give it a moment to process pairing
            await Future.delayed(const Duration(seconds: 3));
          } catch (e) {
            print("Pairing/Bonding failed or not supported: $e");
          }
        }
      } catch (e) {
        print("Bond state check failed (ignorable): $e");
      }

      // Request MTU priority
      if (device.platformName.isNotEmpty) {
        try {
          await device.requestMtu(512);
        } catch (e) {
          print("MTU request failed (ignorable): $e");
        }
      }

      await Future.delayed(const Duration(seconds: 2));

      List<BluetoothService> services = [];

      // Retry loop for service discovery
      for (int i = 0; i < 5; i++) {
        services = await device.discoverServices();
        if (services.isNotEmpty) break;
        print("No services found (Attempt ${i + 1}/5). Waiting...");
        await Future.delayed(const Duration(seconds: 2));
      }

      if (services.isEmpty) {
        print(
          "Still no services. Please UNPAIR the device from Linux Bluetooth settings and try again.",
        );
        _statusController.add("Error: No Services Found. Unpair & Retry.");
        return;
      }

      print("Discovered ${services.length} services");

      bool targetServiceFound = false;

      for (var service in services) {
        print("Service found: ${service.uuid}");

        if (service.uuid.toString().toLowerCase() ==
            serviceUuid.toLowerCase()) {
          print("Found Target Service: $serviceUuid");
          targetServiceFound = true;

          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toLowerCase() ==
                charUuid.toLowerCase()) {
              print("Found Characteristic: $charUuid");
              _targetCharacteristic = characteristic;
              await _setupListener(characteristic);
              break;
            }
          }
          break;
        }
      }

      if (targetServiceFound) {
        _statusController.add("Connected to ${device.platformName}");
      } else {
        print(
          "Connected to ${device.platformName} but it doesn't have our service. Disconnecting...",
        );
        _statusController.add("Wrong device: ${device.platformName}");
        await device.disconnect();
        startScan();
      }
    } catch (e) {
      _statusController.add("Error: $e");
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  Future<void> _setupListener(BluetoothCharacteristic c) async {
    try {
      await c.setNotifyValue(true);
      print("Notifications enabled for ${c.uuid}");
    } catch (e) {
      print("Failed to enable notifications: $e");
      _statusController.add("Notify Error: $e");

      if (e.toString().contains("Too many elements") ||
          e.toString().contains("Bad state")) {
        print("Attempting manual CCCD write fallback...");

        print("--- Descriptors on Characteristic ---");
        for (var d in c.descriptors) {
          print("Descriptor: ${d.uuid} (RemoteId: ${d.remoteId})");
        }
        print("-------------------------------------");

        try {
          final cccdUuid = "00002902-0000-1000-8000-00805f9b34fb";
          final descriptors = c.descriptors
              .where((d) => d.uuid.toString().toLowerCase() == cccdUuid)
              .toList();

          if (descriptors.isNotEmpty) {
            print(
              "Found ${descriptors.length} CCCD descriptors. Writing to first...",
            );
            // Enable Notification: 0x01, 0x00
            await descriptors.first.write([0x01, 0x00]);
            print("Manual CCCD write successful");
            // If manual write works, we consider it a success
            _statusController.add("Connected (Manual CCCD)");
          } else {
            print("No CCCD descriptors found on characteristic.");
          }
        } catch (manualErr) {
          print("Manual CCCD write failed: $manualErr");
        }
      }
    }

    // Always listen to the stream
    c.onValueReceived.listen((value) {
      if (value.isNotEmpty) {
        String msg = utf8.decode(value);
        print("Received from Phone: $msg");
        _messageController.add(msg);
      }
    });
  }

  Future<void> sendToPhone(String text) async {
    if (_targetCharacteristic == null) return;
    await _targetCharacteristic!.write(utf8.encode(text));
  }

  void dispose() {
    _messageController.close();
    _statusController.close();
    _scanResultsController.close();
  }
}
