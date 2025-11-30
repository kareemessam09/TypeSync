import 'dart:async';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class AndroidBluetoothService {
  static const platform = MethodChannel('com.k9.typesync/ble');

  final _messageController = StreamController<String>.broadcast();
  Stream<String> get messageStream => _messageController.stream;

  AndroidBluetoothService() {
    platform.setMethodCallHandler((call) async {
      if (call.method == "onTextReceived") {
        final String msg = call.arguments;
        _messageController.add(msg);
      }
    });
  }

  Future<void> initNativeBluetooth() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ].request();

    try {
      // Call Kotlin function
      await platform.invokeMethod('startServer');
    } on PlatformException catch (e) {
      throw e;
    }
  }

  Future<void> sendText(String text) async {
    try {
      await platform.invokeMethod('sendText', {'text': text});
    } on PlatformException catch (e) {
      throw e;
    }
  }

  void dispose() {
    _messageController.close();
  }
}
