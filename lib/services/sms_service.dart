import 'package:permission_handler/permission_handler.dart';
import 'package:telephony_sms/telephony_sms.dart';

class SmsService {
  final TelephonySMS _telephony = TelephonySMS();
  bool? _hasPermission;

  Future<bool> ensurePermission() async {
    if (_hasPermission == true) return true;

    var permission = await Permission.sms.status;
    if (!permission.isGranted) {
      permission = await Permission.sms.request();
    }
    _hasPermission = permission.isGranted;
    return permission.isGranted;
  }

  Future<void> send({
    required String recipient,
    required String message,
  }) async {
    if (!await ensurePermission()) {
      throw StateError('SMS permission was denied');
    }

    await _telephony.sendSMS(phone: recipient, message: message);
    print('SMS sent to $recipient: $message');
  }
}
