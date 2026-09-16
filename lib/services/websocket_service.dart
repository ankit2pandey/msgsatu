import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_service.dart';

class WebSocketResult {
  final bool isConnected;
  final Device? connectedDevice;
  final List<Map<String, dynamic>> incomingJobs;
  final String? lastError;
  final WebSocketChannel? channel;

  WebSocketResult({
    required this.isConnected,
    this.connectedDevice,
    this.incomingJobs = const [],
    this.lastError,
    this.channel,
  });
}

class WebSocketService {
  WebSocketChannel? _channel;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  Device? _connectedDevice;
  List<Map<String, dynamic>> _incomingJobs = [];
  String? _lastError;

  bool get isConnected => _isConnected;
  Device? get connectedDevice => _connectedDevice;
  List<Map<String, dynamic>> get incomingJobs => _incomingJobs;
  String? get lastError => _lastError;

  Future<void> connect(Device device) async {
    final token = await AuthResult.getToken();
    if (token == null || token.isEmpty) {
      return;
    }

    disconnect();

    final wsUrl = 'wss://sms-back-acto.onrender.com/ws';
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    _channel!.stream.listen((message) {
      try {
        final msg = jsonDecode(message);
        final type = msg['type'];

        switch (type) {
          case 'device_registered':
            _isConnected = true;
            _connectedDevice = device;
            _lastError = null;
            _pingTimer?.cancel();
            _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
              if (_channel != null) {
                _channel!.sink.add(jsonEncode({'type': 'ping'}));
              }
            });
            break;

          case 'pong':
            break;

          case 'sms_job':
            _incomingJobs.insert(0, Map<String, dynamic>.from(msg));
            break;

          case 'error':
            _lastError = msg['message']?.toString();
            break;
        }
      } catch (_) {
        _lastError = 'WebSocket message parse error';
      }
    }, onDone: () {
      _pingTimer?.cancel();
      _pingTimer = null;
      _isConnected = false;

      if (_connectedDevice != null || device.id.isNotEmpty) {
        _reconnectTimer?.cancel();
        _reconnectTimer = Timer(const Duration(seconds: 3), () {
          connect(device);
        });
      }
    });

    _channel!.sink.add(jsonEncode({
      'type': 'device_register',
      'token': token,
      'deviceId': device.androidDeviceId,
      'deviceName': device.deviceName,
      'phoneNumber': device.phoneNumber,
    }));
  }

  void disconnect() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer = null;

    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
    }

    _isConnected = false;
    _connectedDevice = null;
  }

  void sendStatus(String jobId, String recipient, String status, String messageId) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode({
        'type': 'sms_status',
        'jobId': jobId,
        'recipient': recipient,
        'status': status,
        'messageId': messageId,
      }));
    }
  }

  void clearJobs() {
    _incomingJobs.clear();
  }
}
