import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String BASE = 'https://sms-back-acto.onrender.com';

class AuthResult {
  final bool success;
  final String message;
  final String? token;
  final String? email;
  final String? userId;
  final Map<String, dynamic>? data;

  AuthResult({
    required this.success,
    required this.message,
    this.token,
    this.email,
    this.userId,
    this.data,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(json['data'] as Map)
        : <String, dynamic>{};

    final nestedUser = data['user'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(data['user'] as Map)
        : <String, dynamic>{};

    final topUser = json['user'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(json['user'] as Map)
        : <String, dynamic>{};

    final token = (json['token'] ?? data['token'] ?? nestedUser['token'] ?? '')
        .toString();

    final email = (json['email'] ?? nestedUser['email'] ?? topUser['email'] ?? '')
        .toString();

    final userId = (json['id'] ?? data['id'] ?? nestedUser['id'] ?? topUser['id'] ?? '')
        .toString();

    return AuthResult(
      success: json['success'] == true,
      message: (json['message'] ?? 'Login successful').toString(),
      token: token.isNotEmpty ? token : null,
      email: email.isNotEmpty ? email : null,
      userId: userId.isNotEmpty ? userId : null,
      data: data,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'message': message,
        'token': token,
        'email': email,
        'id': userId,
        'data': data,
      };

  static Future<void> save(AuthResult result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_response', jsonEncode(result.toJson()));

      if (result.token != null && result.token!.isNotEmpty) {
        await prefs.setString('auth_token', result.token!);
      }
    } catch (_) {
      // SharedPreferences requires a live Flutter binding in widget apps.
      // In pure Dart tests, keep parsing and return object creation intact.
    }
  }

  static Future<String?> getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('auth_token');
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_response');
      await prefs.remove('auth_token');
    } catch (_) {
      // Same safe guard for test-only or non-widget environments.
    }
  }
}

class Device {
  final String id;
  final String userId;
  final String deviceName;
  final String androidDeviceId;
  final String phoneNumber;
  final String status;
  final String lastSeen;
  final String createdAt;
  final String updatedAt;

  Device({
    required this.id,
    required this.userId,
    required this.deviceName,
    required this.androidDeviceId,
    required this.phoneNumber,
    required this.status,
    required this.lastSeen,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      deviceName: json['deviceName']?.toString() ?? '',
      androidDeviceId: json['androidDeviceId']?.toString() ?? '',
      phoneNumber: json['phoneNumber']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      lastSeen: json['lastSeen']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
    );
  }
}

class DeviceListResult {
  final bool success;
  final String message;
  final List<Device> devices;

  DeviceListResult({required this.success, required this.message, required this.devices});

  factory DeviceListResult.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final list = rawData is List
        ? rawData.map((item) => Device.fromJson(Map<String, dynamic>.from(item))).toList()
        : <Device>[];

    return DeviceListResult(
      success: json['success'] == true,
      message: (json['message'] ?? 'Devices retrieved').toString(),
      devices: list,
    );
  }
}

Future<http.Response> request(
  String path, {
  String method = 'GET',
  Map<String, dynamic>? body,
  http.Client? client,
}) async {
  final actualClient = client ?? http.Client();
  final url = Uri.parse('$BASE$path');

  final headers = <String, String>{
    'Content-Type': 'application/json',
  };

  final token = await AuthResult.getToken();
  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }

  final httpRequest = http.Request(method.toUpperCase(), url)
    ..headers.addAll(headers);

  if (body != null) {
    httpRequest.body = jsonEncode(body);
  }

  final streamedResponse = await actualClient.send(httpRequest);
  final response = await http.Response.fromStream(streamedResponse);

  if (client == null) {
    actualClient.close();
  }

  return response;
}

Future<AuthResult> signup(
  String email,
  String password, {
  http.Client? client,
}) async {
  final response = await request(
    '/api/auth/signup',
    method: 'POST',
    body: {'email': email, 'password': password},
    client: client,
  );

  final payload = jsonDecode(response.body) as Map<String, dynamic>;
  final result = AuthResult.fromJson(payload);
  await AuthResult.save(result);
  return result;
}

Future<AuthResult> login(
  String email,
  String password, {
  http.Client? client,
}) async {
  final response = await request(
    '/api/auth/login',
    method: 'POST',
    body: {'email': email, 'password': password},
    client: client,
  );

  final payload = jsonDecode(response.body) as Map<String, dynamic>;
  final result = AuthResult.fromJson(payload);
  await AuthResult.save(result);
  return result;
}

Future<void> logout({http.Client? client}) async {
  await request('/api/auth/logout', method: 'POST', client: client);
  await AuthResult.clear();
}

Future<DeviceListResult> listDevices({http.Client? client}) async {
  final response = await request('/api/devices', method: 'GET', client: client);
  final payload = jsonDecode(response.body) as Map<String, dynamic>;
  return DeviceListResult.fromJson(payload);
}
