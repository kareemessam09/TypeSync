import 'dart:io';
import 'package:flutter/material.dart';
import 'package:typesync/AndroidNativePeer.dart';
import 'package:typesync/LinuxPeer.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Platform.isAndroid ? const AndroidNativePeer() : const LinuxPeer(),
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
    );
  }
}
