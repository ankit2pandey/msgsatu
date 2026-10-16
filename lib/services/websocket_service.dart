import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_service.dart';
import 'sms_service.dart';

typedef WebSocketStateCallback =
    void Function(
      bool connected,
      Device? device,
      List<Map<String, dynamic>> jobs,
      String? error,
    );

class WebSocketService {
  WebSocketService({
    this.onState,
    this.isJobProcessed,
    this.markJobProcessed,
    this.getJobStatuses,
    this.saveJobStatus,
    this.saveJobs,
  });

  final WebSocketStateCallback? onState;
  final Future<bool> Function(String jobId)? isJobProcessed;
  final Future<void> Function(String jobId)? markJobProcessed;
  final Future<Map<String, String>> Function(String jobId)? getJobStatuses;
  final Future<void> Function(String jobId, String recipient, String status)?
  saveJobStatus;
  final Future<void> Function(List<Map<String, dynamic>> jobs)? saveJobs;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  Timer? _pongTimeoutTimer;
  Timer? _reconnectTimer;
  bool _connecting = false;
  bool _isConnected = false;
  bool _manualDisconnect = false;
  int _reconnectAttempt = 0;
  Device? _connectedDevice;
  List<Map<String, dynamic>> _incomingJobs = [];
  String? _lastError;
  final Set<String> _jobsInProgress = <String>{};
  final SmsService _smsService = SmsService();

  bool get isConnected => _isConnected;
  Device? get connectedDevice => _connectedDevice;
  List<Map<String, dynamic>> get incomingJobs => _incomingJobs;
  String? get lastError => _lastError;

  Future<void> connect(Device device) async {
    if (_connecting || (_isConnected && _connectedDevice?.id == device.id)) {
      return;
    }
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    _connecting = true;
    _connectedDevice = device;
    _emit();

    try {
      final token = await AuthResult.getToken();
      if (token == null || token.isEmpty) {
        throw StateError(
          'No saved login token. Sign in again to start the service.',
        );
      }

      final channel = WebSocketChannel.connect(
        Uri.parse('wss://sms-back-acto.onrender.com/ws'),
      );
      _channel = channel;
      await channel.ready;
      if (_manualDisconnect || _channel != channel) return;

      _subscription = channel.stream.listen(
        _handleMessage,
        onError: (Object error, StackTrace stack) => _connectionEnded(error),
        onDone: () => _connectionEnded(null),
        cancelOnError: true,
      );
      channel.sink.add(
        jsonEncode({
          'type': 'device_register',
          'token': token,
          'deviceId': device.androidDeviceId,
          'deviceName': device.deviceName,
          'phoneNumber': device.phoneNumber,
        }),
      );
    } catch (error) {
      _lastError = 'WebSocket connection failed: $error';
      _connectionEnded(error);
    } finally {
      _connecting = false;
      _emit();
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final msg = jsonDecode(message as String) as Map<String, dynamic>;
      switch (msg['type']) {
        case 'device_registered':
          _isConnected = true;
          _reconnectAttempt = 0;
          _lastError = null;
          _pingTimer?.cancel();
          _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
            final channel = _channel;
            if (_isConnected && channel != null) {
              try {
                channel.sink.add(jsonEncode({'type': 'ping'}));
                if (onState != null) {
                  _pongTimeoutTimer?.cancel();
                  _pongTimeoutTimer = Timer(const Duration(seconds: 20), () {
                    final current = _channel;
                    if (_isConnected && current != null) {
                      _connectionEnded(
                        TimeoutException('WebSocket pong timed out'),
                      );
                      current.sink.close();
                    }
                  });
                }
              } catch (error) {
                _connectionEnded(error);
              }
            }
          });
          _emit();
          break;
        case 'sms_job':
          final job = Map<String, dynamic>.from(msg);
          final jobId = job['jobId']?.toString() ?? '';
          if (jobId.isEmpty || _jobsInProgress.contains(jobId)) break;
          _jobsInProgress.add(jobId);
          _incomingJobs.insert(0, job);
          if (_incomingJobs.length > 100) {
            _incomingJobs = _incomingJobs.take(100).toList();
          }
          saveJobs?.call(_incomingJobs);
          _emit();
          unawaited(_sendJob(job));
          break;
        case 'error':
          _lastError = msg['message']?.toString();
          _emit();
          break;
        case 'pong':
          _pongTimeoutTimer?.cancel();
          _pongTimeoutTimer = null;
          break;
      }
    } catch (error) {
      _lastError = 'WebSocket message parse error: $error';
      _emit();
    }
  }

  Future<void> _sendJob(Map<String, dynamic> job) async {
    final jobId = job['jobId']?.toString() ?? '';
    if (jobId.isEmpty) return;
    try {
      if (await (isJobProcessed?.call(jobId) ?? Future.value(false))) {
        final statuses =
            await getJobStatuses?.call(jobId) ?? <String, String>{};
        for (final entry in statuses.entries) {
          sendStatus(jobId, entry.key, entry.value, '');
        }
        return;
      }
      // Persist the claim before sending so reconnects cannot resend this job.
      await markJobProcessed?.call(jobId);

      final message = job['message']?.toString() ?? '';
      final rawRecipients = job['recipients'];
      final recipients = rawRecipients is List
          ? rawRecipients
                .map((value) => value.toString().trim())
                .where((value) => value.isNotEmpty)
          : const <String>[];
      if (message.isEmpty || recipients.isEmpty) {
        _lastError =
            'Received an SMS job with missing jobId, message, or recipients';
        _emit();
        return;
      }

      for (final recipient in recipients) {
        var status = 'sent';
        try {
          await _smsService.send(recipient: recipient, message: message);
        } catch (error) {
          status = 'failed';
          _lastError = 'SMS to $recipient failed: $error';
        }
        await saveJobStatus?.call(jobId, recipient, status);
        sendStatus(jobId, recipient, status, '');
        _emit();
      }
    } catch (error) {
      _lastError = 'Could not process SMS job $jobId: $error';
      _emit();
    } finally {
      _jobsInProgress.remove(jobId);
    }
  }

  void _connectionEnded(Object? error) {
    _pingTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    _pingTimer = null;
    _pongTimeoutTimer = null;
    _isConnected = false;
    _connecting = false;
    _subscription = null;
    _channel = null;
    if (error != null) _lastError = 'WebSocket disconnected: $error';
    _emit();

    if (!_manualDisconnect && _connectedDevice != null) {
      _reconnectTimer?.cancel();
      final seconds = onState == null
          ? 3
          : (1 << _reconnectAttempt.clamp(0, 5)).clamp(1, 30);
      _reconnectAttempt++;
      _reconnectTimer = Timer(Duration(seconds: seconds), () {
        final device = _connectedDevice;
        if (!_manualDisconnect && device != null) unawaited(connect(device));
      });
    }
  }

  void _emit() =>
      onState?.call(_isConnected, _connectedDevice, _incomingJobs, _lastError);

  void disconnect() {
    _manualDisconnect = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _connecting = false;
    _connectedDevice = null;
    _emit();
  }

  void sendStatus(
    String jobId,
    String recipient,
    String status,
    String messageId,
  ) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(
        jsonEncode({
          'type': 'sms_status',
          'jobId': jobId,
          'recipient': recipient,
          'status': status,
          'messageId': messageId,
        }),
      );
    }
  }
}
