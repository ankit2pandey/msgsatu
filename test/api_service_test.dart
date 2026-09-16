import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_first_app/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('signup, login, logout and listDevices use the configured backend base', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/auth/signup') {
        expect(request.method, 'POST');
        expect(request.url.host, 'sms-back-acto.onrender.com');
        expect(request.url.scheme, 'https');

        final body = jsonDecode(request.body);
        expect(body['email'], 'test@example.com');
        expect(body['password'], 'secret123');

        return http.Response(
          '{"success": true, "message": "Account created successfully", "token": "signup-token"}',
          200,
        );
      }

      if (request.url.path == '/api/auth/login') {
        expect(request.method, 'POST');

        final body = jsonDecode(request.body);
        expect(body['email'], 'test@example.com');
        expect(body['password'], 'secret123');

        return http.Response(
          '{"success": true, "message": "Login successful", "token": "login-token"}',
          200,
        );
      }

      if (request.url.path == '/api/auth/logout') {
        expect(request.method, 'POST');
        return http.Response('{"success": true}', 200);
      }

      if (request.url.path == '/api/devices') {
        expect(request.method, 'GET');
        return http.Response(
          '{"success": true, "message": "Devices retrieved", "data": [{"id": "486fe10f-c714-4b26-8b93-0557656aeede", "userId": "ba3edb42-4ebc-4eee-8f83-3b7ea9512133", "deviceName": "uuguw", "androidDeviceId": "invalid_typew", "phoneNumber": "+917566035890", "status": "offline", "lastSeen": "2026-09-12T16:09:00.916Z", "createdAt": "2026-09-09T15:40:11.676Z", "updatedAt": "2026-09-12T16:18:03.713Z"}]}',
          200,
        );
      }

      return http.Response('not found', 404);
    });

    final signupResult = await signup('test@example.com', 'secret123', client: client);
    final loginResult = await login('test@example.com', 'secret123', client: client);

    expect(signupResult.success, isTrue);
    expect(signupResult.message, 'Account created successfully');
    expect(signupResult.token, 'signup-token');

    expect(loginResult.success, isTrue);
    expect(loginResult.message, 'Login successful');
    expect(loginResult.token, 'login-token');

    await logout(client: client);
    final devices = await listDevices(client: client);
    expect(devices.success, isTrue);
    expect(devices.message, 'Devices retrieved');
    expect(devices.devices.length, 1);
    expect(devices.devices.first.deviceName, 'uuguw');
  });
}
