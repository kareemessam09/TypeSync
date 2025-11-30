import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/android_bluetooth_service.dart';

class AndroidNativePeer extends StatefulWidget {
  const AndroidNativePeer({super.key});

  @override
  State<AndroidNativePeer> createState() => _AndroidNativePeerState();
}

class _AndroidNativePeerState extends State<AndroidNativePeer> {
  final AndroidBluetoothService _bluetoothService = AndroidBluetoothService();
  final TextEditingController _controller = TextEditingController();

  List<Map<String, String>> messages = [];
  String status = "Initializing...";
  bool isServerRunning = false;

  @override
  void initState() {
    super.initState();
    _initNativeBluetooth();

    _bluetoothService.messageStream.listen((msg) {
      setState(() {
        messages.insert(0, {'sender': 'laptop', 'text': msg});
      });
    });
  }

  Future<void> _initNativeBluetooth() async {
    try {
      setState(() => status = "Starting BLE Server...");
      await _bluetoothService.initNativeBluetooth();
      setState(() {
        status = "BLE Server Running";
        isServerRunning = true;
      });
    } on PlatformException catch (e) {
      setState(() {
        status = "Error: ${e.message}";
        isServerRunning = false;
      });
    }
  }

  Future<void> _sendText() async {
    if (_controller.text.trim().isEmpty) return;
    try {
      await _bluetoothService.sendText(_controller.text);

      setState(() {
        messages.insert(0, {'sender': 'me', 'text': _controller.text});
        _controller.clear();
      });
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to send: ${e.message}")));
    }
  }

  @override
  void dispose() {
    _bluetoothService.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("TypeSync - Android"),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: "Restart Server",
            onPressed: _initNativeBluetooth,
          ),
        ],
      ),
      body: Column(
        children: [
          // Status Bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: isServerRunning ? Colors.blue.shade100 : Colors.red.shade100,
            child: Row(
              children: [
                Icon(
                  isServerRunning
                      ? Icons.bluetooth_audio
                      : Icons.bluetooth_disabled,
                  color: isServerRunning
                      ? Colors.blue.shade800
                      : Colors.red.shade800,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    style: TextStyle(
                      color: isServerRunning
                          ? Colors.blue.shade900
                          : Colors.red.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Chat Area
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Waiting for messages...",
                          style: TextStyle(color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMe = msg['sender'] == 'me';
                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: GestureDetector(
                          onLongPress: () {
                            Clipboard.setData(
                              ClipboardData(text: msg['text'] ?? ""),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Message copied to clipboard"),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.75,
                            ),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? Colors.blue.shade600
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: isMe
                                    ? const Radius.circular(16)
                                    : const Radius.circular(4),
                                bottomRight: isMe
                                    ? const Radius.circular(4)
                                    : const Radius.circular(16),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg['text'] ?? "",
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: isMe ? Colors.white : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isMe ? "Me" : "Laptop",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isMe
                                        ? Colors.white.withOpacity(0.7)
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Input Area
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: "Type message...",
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _sendText(),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.blue.shade600,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
