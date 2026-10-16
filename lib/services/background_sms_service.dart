import 'dart:async';
import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'sms_service.dart';
import 'websocket_service.dart';

const _channelId = 'tachneat_sms_service';
const _notificationId = 7153;
const _deviceKey = 'background_sms_device';
const _jobsKey = 'background_sms_jobs';
const _processedKey = 'background_sms_processed_ids';
const _jobStatusesKey = 'background_sms_job_statuses';

class BackgroundSmsService {
  BackgroundSmsService._();
  static final BackgroundSmsService instance = BackgroundSmsService._();

  final FlutterBackgroundService _service = FlutterBackgroundService();
  StreamSubscription<Map<String, dynamic>?>? _subscription;
  final ValueNotifier<Map<String, dynamic>> state = ValueNotifier({
    'running': false,
    'connected': false,
    'jobs': <Map<String, dynamic>>[],
  });

  Future<void> initialize() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: backgroundSmsServiceEntryPoint,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        notificationChannelId: _channelId,
        initialNotificationTitle: 'Tachneat SMS Service',
        initialNotificationContent: 'Listening for jobs.',
        foregroundServiceNotificationId: _notificationId,
        foregroundServiceTypes: const [AndroidForegroundType.remoteMessaging],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
    await _restoreState();
    _listen();
  }

  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    state.value = {
      ...state.value,
      'running': await _service.isRunning(),
      'jobs': _decodeJobs(prefs.getString(_jobsKey)),
      'device': _decodeMap(prefs.getString(_deviceKey)),
    };
  }

  void _listen() {
    _subscription?.cancel();
    _subscription = _service.on('state').listen((event) {
      if (event != null) state.value = {...state.value, ...event};
    });
  }

  Future<void> start(Device device) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final notification = await Permission.notification.request();
    if (!notification.isGranted) {
      throw StateError(
        'Notification permission is required to show the running service.',
      );
    }
    if (!await SmsService().ensurePermission()) {
      throw StateError('SMS permission is required to send SMS jobs.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceKey, jsonEncode(device.toJson()));
    await _restoreState();
    if (await _service.isRunning()) {
      _service.invoke('configure', device.toJson());
    } else {
      await _service.startService();
    }
    state.value = {...state.value, 'running': true, 'device': device.toJson()};
  }

  Future<void> stop() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceKey);
    _service.invoke('stop');
    state.value = {
      ...state.value,
      'running': false,
      'connected': false,
      'device': null,
    };
  }

  void requestState() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      _service.invoke('get_state');
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    state.dispose();
  }
}

@pragma('vm:entry-point')
Future<void> backgroundSmsServiceEntryPoint(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final ws = WebSocketService(
    onState: (connected, device, jobs, error) {
      service.invoke('state', {
        'running': true,
        'connected': connected,
        'device': device?.toJson(),
        'jobs': jobs,
        'error': error,
      });
    },
    isJobProcessed: (jobId) async {
      final current = (prefs.getStringList(_processedKey) ?? <String>[])
          .toSet();
      return current.contains(jobId);
    },
    getJobStatuses: (jobId) async {
      final all = _decodeMap(prefs.getString(_jobStatusesKey)) ?? {};
      final raw = all[jobId];
      if (raw is! Map) return <String, String>{};
      return raw.map(
        (key, value) =>
            MapEntry<String, String>(key.toString(), value.toString()),
      );
    },
    markJobProcessed: (jobId) async {
      final current = (prefs.getStringList(_processedKey) ?? <String>[])
          .toSet();
      current.add(jobId);
      await prefs.setStringList(
        _processedKey,
        current.toList().reversed.take(500).toList().reversed.toList(),
      );
    },
    saveJobStatus: (jobId, recipient, status) async {
      final all = _decodeMap(prefs.getString(_jobStatusesKey)) ?? {};
      final statuses = all[jobId] is Map
          ? Map<String, dynamic>.from(all[jobId] as Map)
          : <String, dynamic>{};
      statuses[recipient] = status;
      all[jobId] = statuses;
      final bounded = all.entries.toList().reversed.take(500).toList().reversed;
      await prefs.setString(
        _jobStatusesKey,
        jsonEncode(Map.fromEntries(bounded)),
      );
    },
    saveJobs: (jobs) async => prefs.setString(_jobsKey, jsonEncode(jobs)),
  );

  Future<void> configure(Map<String, dynamic>? map) async {
    final raw = map ?? _decodeMap(prefs.getString(_deviceKey));
    if (raw != null) {
      ws.connect(Device.fromJson(raw));
      if (service is AndroidServiceInstance) {
        await service.setForegroundNotificationInfo(
          title: 'Tachneat SMS Service',
          content: 'Listening for jobs.',
        );
      }
    }
  }

  service.on('configure').listen((event) => configure(event));
  service
      .on('get_state')
      .listen(
        (_) => service.invoke('state', {
          'running': true,
          'connected': ws.isConnected,
          'device': ws.connectedDevice?.toJson(),
          'jobs': ws.incomingJobs,
          'error': ws.lastError,
        }),
      );
  service.on('stop').listen((_) {
    ws.disconnect();
    service.invoke('state', {
      'running': false,
      'connected': false,
      'device': null,
    });
    service.stopSelf();
  });
  await configure(null);
}

Map<String, dynamic>? _decodeMap(String? value) {
  if (value == null) return null;
  try {
    return Map<String, dynamic>.from(jsonDecode(value) as Map);
  } catch (_) {
    return null;
  }
}

List<Map<String, dynamic>> _decodeJobs(String? value) {
  if (value == null) return <Map<String, dynamic>>[];
  try {
    return (jsonDecode(value) as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  } catch (_) {
    return <Map<String, dynamic>>[];
  }
}
