import 'dart:async';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  List<Device> _devices = [];
  String? _error;
  
  final WebSocketService _wsService = WebSocketService();
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _fetchDevices();
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _wsService.disconnect();
    super.dispose();
  }

  Future<void> _fetchDevices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await listDevices();
      if (result.success) {
        setState(() {
          _devices = result.devices;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = result.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load devices: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    await logout();
    _wsService.disconnect();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _connectToDevice(Device device) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connecting to ${device.deviceName}...', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF6366F1), // Indigo 500
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ),
      );
      await _wsService.connect(device);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to connect: $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF94A3B8)),
            onPressed: _fetchDevices,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF94A3B8)),
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildConnectionStatusBanner(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _fetchDevices,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _wsService.isConnected 
                        ? _buildJobsList() 
                        : _devices.isEmpty
                            ? const Center(
                                child: Text(
                                  'No devices found.',
                                  style: TextStyle(color: Color(0xFF94A3B8)),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _devices.length,
                                itemBuilder: (context, index) {
                                  final device = _devices[index];
                                  return _buildDeviceCard(device);
                                },
                              ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatusBanner() {
    final isConnected = _wsService.isConnected;
    final connectedDevice = _wsService.connectedDevice;
    
    if (!isConnected && connectedDevice == null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B), // Slate 800
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF334155)), // Slate 700
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF94A3B8)),
            const SizedBox(width: 16),
            const Text(
              'No device currently connected',
              style: TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    final accentColor = isConnected ? const Color(0xFF10B981) : const Color(0xFF6366F1); // Emerald or Indigo

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.check_circle_rounded : Icons.sync_rounded,
            color: accentColor,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected ? 'Connected' : 'Connecting...',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  connectedDevice?.deviceName ?? 'Unknown Device',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          if (isConnected)
            TextButton(
              onPressed: () {
                _wsService.disconnect();
                setState(() {});
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Disconnect'),
            )
        ],
      ),
    );
  }

  Widget _buildDeviceCard(Device device) {
    final isCurrentlyConnected = _wsService.connectedDevice?.id == device.id;
    final isOnline = device.status == 'online';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B), // Slate 800
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)), // Slate 700
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A), // Slate 900
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.smartphone, color: Color(0xFF94A3B8), size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.deviceName.isNotEmpty ? device.deviceName : 'Unknown Device',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        device.phoneNumber,
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOnline ? const Color(0xFF10B981).withOpacity(0.1) : const Color(0xFF64748B).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isOnline ? const Color(0xFF10B981).withOpacity(0.2) : const Color(0xFF64748B).withOpacity(0.2),
                    ),
                  ),
                  child: Text(
                    device.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: isOnline ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Last seen', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                      const SizedBox(height: 2),
                      Text(
                        device.lastSeen.isNotEmpty ? _formatDate(device.lastSeen) : 'N/A',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
                isCurrentlyConnected
                    ? ElevatedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Connected'),
                        style: ElevatedButton.styleFrom(
                          disabledBackgroundColor: const Color(0xFF6366F1).withOpacity(0.1),
                          disabledForegroundColor: const Color(0xFF6366F1),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                          minimumSize: const Size(0, 36),
                        ),
                      )
                    : ElevatedButton(
                        onPressed: () => _connectToDevice(device),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF334155), // Slate 700
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                          minimumSize: const Size(0, 36),
                        ),
                        child: const Text('Connect', style: TextStyle(fontWeight: FontWeight.w500)),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobsList() {
    final jobs = _wsService.incomingJobs;

    if (jobs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Color(0xFF334155)), // Slate 700
            SizedBox(height: 16),
            Text(
              'No SMS jobs received yet',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Listening for incoming messages...',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Jobs',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.2)),
                ),
                child: Text(
                  '${jobs.length} Total',
                  style: const TextStyle(
                    color: Color(0xFF818CF8), // Indigo 400
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: jobs.length,
            itemBuilder: (context, index) {
              final job = jobs[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B), // Slate 800
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155)), // Slate 700
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.message_outlined, color: Color(0xFF38BDF8), size: 18), // Light Blue
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Builder(builder: (_) {
                              final rawRecipients = job['recipients'];
                              final recipientsText = rawRecipients is List
                                  ? rawRecipients.map((e) => e.toString()).join(', ')
                                  : (rawRecipients?.toString() ?? 'Unknown Recipient');
                              return Text(
                                recipientsText,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              );
                            }),
                          ),
                          Flexible(
                            child: Text(
                              'Job #${job['jobId']?.toString() ?? '?'}',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          job['message']?.toString() ?? 'No content',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateString;
    }
  }
}
