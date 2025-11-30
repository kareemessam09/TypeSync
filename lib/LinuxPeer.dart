// ---------------------------------------------------------
// 💻 LINUX SIDE (Uses flutter_blue_plus)
// ---------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/linux_bluetooth_service.dart';

class LinuxPeer extends StatefulWidget {
  const LinuxPeer({super.key});

  @override
  State<LinuxPeer> createState() => _LinuxPeerState();
}

class _LinuxPeerState extends State<LinuxPeer> {
  final LinuxBluetoothService _bluetoothService = LinuxBluetoothService();
  final TextEditingController _controller = TextEditingController();

  List<Map<String, String>> messages = [];
  String status = "Initializing...";
  bool isConnected = false;
  List<dynamic> scanResults = [];

  @override
  void initState() {
    super.initState();
    _startScan();

    _bluetoothService.statusStream.listen((newStatus) {
      setState(() {
        status = newStatus;
        isConnected = newStatus.toLowerCase().startsWith("connected to");
      });
    });

    _bluetoothService.messageStream.listen((msg) {
      setState(() {
        messages.insert(0, {'sender': 'phone', 'text': msg});
      });
    });

    _bluetoothService.scanResultsStream.listen((results) {
      setState(() {
        scanResults = results;
      });
    });
  }

  void _startScan() {
    _bluetoothService.startScan();
  }

  Future<void> _connectToDevice(dynamic device) async {
    await _bluetoothService.connectToDevice(device);
  }

  Future<void> _sendToPhone() async {
    if (_controller.text.trim().isEmpty) return;

    try {
      await _bluetoothService.sendToPhone(_controller.text);
      setState(() {
        messages.insert(0, {'sender': 'me', 'text': _controller.text});
        _controller.clear();
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to send: $e")));
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
        title: const Text("TypeSync - Linux"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Restart Scan",
            onPressed: () {
              _bluetoothService.startScan();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Status Bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: isConnected ? Colors.green.shade100 : Colors.orange.shade100,
            child: Row(
              children: [
                Icon(
                  isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_searching,
                  color: isConnected
                      ? Colors.green.shade800
                      : Colors.orange.shade800,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    style: TextStyle(
                      color: isConnected
                          ? Colors.green.shade900
                          : Colors.orange.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (!isConnected)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      "Available Devices:",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: scanResults.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            itemCount: scanResults.length,
                            itemBuilder: (context, index) {
                              final result = scanResults[index];
                              return ListTile(
                                leading: const Icon(Icons.bluetooth),
                                title: Text(
                                  result.device.platformName.isNotEmpty
                                      ? result.device.platformName
                                      : "Unknown Device",
                                ),
                                subtitle: Text(
                                  result.device.remoteId.toString(),
                                ),
                                trailing: ElevatedButton(
                                  child: const Text("Connect"),
                                  onPressed: () =>
                                      _connectToDevice(result.device),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),

          if (isConnected)
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Text(
                        "No messages yet",
                        style: TextStyle(color: Colors.grey.shade400),
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
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? Colors.blue.shade100
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isMe ? "Me" : "Phone",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isMe
                                          ? Colors.blue.shade800
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                  Text(
                                    msg['text'] ?? "",
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: isConnected,
                    decoration: InputDecoration(
                      hintText: isConnected
                          ? "Type a message..."
                          : "Waiting for connection...",
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: isConnected
                          ? Colors.white
                          : Colors.grey.shade100,
                    ),
                    onSubmitted: (_) => _sendToPhone(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  onPressed: isConnected ? _sendToPhone : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
