import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const ParkingMonitor(),
    );
  }
}

class ParkingMonitor extends StatefulWidget {
  const ParkingMonitor({super.key});

  @override
  _ParkingMonitorState createState() => _ParkingMonitorState();
}

class _ParkingMonitorState extends State<ParkingMonitor>
    with WidgetsBindingObserver {
  late IOWebSocketChannel imageChannel;
  late IOWebSocketChannel dataChannel;
  Uint8List? imageBytes;
  Uint8List? snapshotImage;
  int occupiedSlots = 0;
  int totalSlots = 3;
  Timer? debounceTimer;
  bool showSnapshot = false;
  int? previousOccupiedSlots;
  bool isConnected = false;
  DateTime? lastDataReceivedTime;
  Timer? connectionCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWebSockets();
    _startConnectionChecker();
  }

  void _initWebSockets() {
    _connectImageWebSocket();
    _connectDataWebSocket();
  }

  void _connectImageWebSocket() {
    try {
      print('🔄 Connecting WebSocket image...');
      imageChannel = IOWebSocketChannel.connect(
        'ws://192.168.0.103:3000',
        headers: {'Connection': 'Upgrade', 'Upgrade': 'websocket'},
        pingInterval: const Duration(seconds: 5),
      );

      imageChannel.stream.listen(
        (data) {
          _handleImageData(data);
        },
        onError: (error) {
          print('❌ Image WebSocket error: $error');
          _handleDisconnection();
        },
        onDone: () {
          print('⚠️ Image WebSocket closed');
          _handleDisconnection();
        },
      );
    } catch (e) {
      print('❌ Error initializing image WebSocket:$e');
      _handleDisconnection();
    }
  }

  void _connectDataWebSocket() {
    try {
      print('🔄 Connecting to WebSocket data...');
      dataChannel = IOWebSocketChannel.connect(
        'ws://192.168.0.103:3001',
        headers: {'Connection': 'Upgrade', 'Upgrade': 'websocket'},
        pingInterval: const Duration(seconds: 5),
      );

      dataChannel.stream.listen(
        (data) {
          _handleDataMessage(data);
        },
        onError: (error) {
          print('❌ WebSocket data error: $error');
          _handleDisconnection();
        },
        onDone: () {
          print('⚠️ WebSocket data closed');
          _handleDisconnection();
        },
      );
    } catch (e) {
      print('❌ Error initializing WebSocket data: $e');
      _handleDisconnection();
    }
  }

  void _handleImageData(dynamic data) {
    if (data is List<int>) {
      debounceTimer?.cancel();
      debounceTimer = Timer(const Duration(milliseconds: 100), () {
        try {
          final bytes = Uint8List.fromList(data);
          if (bytes.lengthInBytes > 100) {
            // Kiểm tra dữ liệu hợp lệ
            setState(() {
              imageBytes = bytes;
              isConnected = true;
            });
          }
        } catch (e) {
          print('❌ Image data processing error: $e');
        }
      });
    }
  }

  void _handleDataMessage(dynamic data) {
    try {
      setState(() {
        lastDataReceivedTime = DateTime.now();
        isConnected = true;
      });

      final jsonString = data is List<int> ? utf8.decode(data) : data;
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;

      if (jsonData.containsKey('occupiedSlots') &&
          jsonData.containsKey('totalSlots')) {
        final newOccupied = jsonData['occupiedSlots'] as int;
        final newTotal = jsonData['totalSlots'] as int;

        if (previousOccupiedSlots != null &&
            newOccupied != previousOccupiedSlots) {}

        setState(() {
          occupiedSlots = newOccupied;
          totalSlots = newTotal;
          previousOccupiedSlots = newOccupied;
        });
      }
    } catch (e) {
      print('❌ Data processing error: $e');
    }
  }

  void _startConnectionChecker() {
    connectionCheckTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (lastDataReceivedTime != null &&
          DateTime.now().difference(lastDataReceivedTime!) >
              const Duration(seconds: 15)) {
        print('⚠️ No data received for 15 seconds');
        _handleDisconnection();
      }
    });
  }

  void _handleDisconnection() {
    if (mounted) {
      setState(() {
        isConnected = false;
      });
      _reconnectWebSockets();
    }
  }

  void _reconnectWebSockets() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _disposeWebSockets();
        _initWebSockets();
      }
    });
  }

  void _disposeWebSockets() {
    try {
      imageChannel.sink.close();
      dataChannel.sink.close();
    } catch (e) {
      print('❌ Error closing WebSocket: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initWebSockets();
    } else if (state == AppLifecycleState.paused) {
      _disposeWebSockets();
    }
  }

  @override
  void dispose() {
    _disposeWebSockets();
    debounceTimer?.cancel();
    connectionCheckTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Parking'),
        centerTitle: true,
        actions: [
          Icon(
            isConnected ? Icons.wifi : Icons.wifi_off,
            color: isConnected ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildVideoDisplay()),
          _buildParkingInfoSection(),
        ],
      ),
    );
  }

  Widget _buildVideoDisplay() {
    return Stack(
      children: [
        // Hiển thị stream video thông thường
        if (!showSnapshot && imageBytes != null)
          Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                imageBytes!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) {
                  return _buildErrorDisplay('Error loading live video');
                },
              ),
            ),
          ),

        // Hiển thị snapshot khi có thay đổi
        if (showSnapshot && snapshotImage != null)
          Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red, width: 3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Image.memory(
                    snapshotImage!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildErrorDisplay('Error loading photo');
                    },
                  ),
                ],
              ),
            ),
          ),

        // Hiển thị khi đang tải hoặc mất kết nối
        if (imageBytes == null || !isConnected)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!isConnected)
                  const Icon(Icons.wifi_off, size: 50, color: Colors.red)
                else
                  const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  !isConnected ? 'Reconnecting...' : 'Loading images...',
                  style: const TextStyle(fontSize: 18),
                ),
                if (!isConnected)
                  TextButton(
                    onPressed: _initWebSockets,
                    child: const Text('Try again'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildErrorDisplay(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error, color: Colors.red, size: 50),
          const SizedBox(height: 10),
          Text(message, style: TextStyle(color: Colors.red[700], fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildParkingInfoSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Text(
            'PARKING STATUS',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildParkingInfoBox(
                'Total seats',
                totalSlots.toString(),
                Colors.blue,
                Icons.local_parking,
              ),
              _buildParkingInfoBox(
                'Passed',
                occupiedSlots.toString(),
                Colors.orange,
                Icons.car_repair,
              ),
              _buildParkingInfoBox(
                'Available',
                (totalSlots - occupiedSlots).toString(),
                Colors.green,
                Icons.emoji_transportation,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParkingInfoBox(
    String title,
    String value,
    Color color,
    IconData icon,
  ) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          width: 80,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: color, width: 2),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 5),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
