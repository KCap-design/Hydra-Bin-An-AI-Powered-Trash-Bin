import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hydra_host/services/host_service.dart';
import 'package:hydra_host/screens/ai_processing_screen.dart';

class HostScreen extends StatefulWidget {
  const HostScreen({super.key});

  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  String _status = 'Initializing...';
  String _pairingCode = '';
  String _connectedUserName = '';
  StreamSubscription<DocumentSnapshot>? _sessionSubscription;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      setState(() => _status = 'Testing Firebase connection...');
      await HostService.testConnection();

      setState(() => _status = 'Generating pairing code...');
      await HostService.createSessionDocument();
      _pairingCode = HostService.getCurrentCode();

      setState(() => _status = 'Ready - Waiting for connection');
      _startSessionListener();
    } catch (e) {
      setState(() => _status = 'Error: $e');
      print('Initialization error: $e');
    }
  }

  void _startSessionListener() {
    _sessionSubscription = HostService.listenForSessionStatus().listen(
      (snapshot) async {
        if (snapshot.exists && mounted) {
          final data = snapshot.data() as Map<String, dynamic>;
          final String status = data['status'] ?? 'waiting';
          final String connectedUserId =
              HostService.getConnectedUserId(snapshot) ?? '';

          // Get user info from connected_user field
          final userInfo = HostService.getUserInfoFromSession(snapshot);

          print('=== Session Update ===');
          print('Status: $status');
          print('Connected User ID: $connectedUserId');
          print('User Info: $userInfo');
          print('Full session data: $data');

          if (status == 'connected' && userInfo != null) {
            print('User connected - calling _handleUserConnected');
            _handleUserConnected(userInfo, snapshot);
          } else if (status == 'processing' && userInfo != null) {
            print('Processing started - user is in AI classification');
            // Extract UID if not already done
            await HostService.updateConnectedUserId(snapshot);
            _handleProcessing(userInfo, snapshot);
          } else if (status == 'completed') {
            print('Session completed - ignoring (handled by countdown)');
          } else {
            print('Status: $status, waiting for next action...');
            // Also try to extract UID if we have user info but status is waiting
            if (userInfo != null) {
              print('Found user info in waiting status - extracting UID');
              await HostService.updateConnectedUserId(snapshot);
            }
          }
        }
      },
      onError: (error) {
        print('Session listener error: $error');
        if (mounted) {
          setState(() => _status = 'Connection Error: $error');
        }
      },
    );
  }

  Future<void> _handleUserConnected(
    Map<String, dynamic> userInfo,
    DocumentSnapshot snapshot,
  ) async {
    print('=== _handleUserConnected Called ===');
    print('User info received: $userInfo');

    setState(() => _status = 'User connected!');

    // Extract UID from connected_user and update connected_user_uid field
    print('Calling updateConnectedUserId...');
    await HostService.updateConnectedUserId(snapshot);
    print('updateConnectedUserId completed.');

    // Get user name from connected_user
    final userName = userInfo['name'] ?? userInfo['email'] ?? 'Unknown User';
    print('User name: $userName');

    setState(() => _connectedUserName = userName);

    // Show connection notification
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$userName connected! Processing started...'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );

    // Navigate to AI processing screen after a short delay
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && !_hasNavigated) {
        _hasNavigated = true;
        print('Navigating to AI processing screen...');
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => AIProcessingScreen(
              scannedContent: 'Connected: $userName\nCode: $_pairingCode',
              userInfo: userInfo,
              sessionSnapshot: snapshot,
              hostService: HostService,
            ),
          ),
        );
      }
    });
  }

  void _handleProcessing(
    Map<String, dynamic> userInfo,
    DocumentSnapshot snapshot,
  ) {
    setState(() => _status = 'Processing...');
    
    // The Host app should be the one doing the processing (classification)
    // Navigate to AI processing screen
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && !_hasNavigated) {
        _hasNavigated = true;
        print('Navigating to AI processing screen...');
        final userName = userInfo['name'] ?? userInfo['email'] ?? 'Unknown User';
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => AIProcessingScreen(
              scannedContent: 'Processing User: $userName',
              userInfo: userInfo,
              sessionSnapshot: snapshot,
              hostService: HostService,
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2C),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Text(
                      'TRASH SORTER HOST',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '6-Digit Pairing System',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _status,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_connectedUserName.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Connected: $_connectedUserName',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // 6-Digit Code Display
              Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      'YOUR PAIRING CODE',
                      style: TextStyle(
                        fontSize: 20,
                        color: Color(0xFF666666),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _pairingCode.isEmpty ? '------' : _pairingCode,
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E1E1E),
                        letterSpacing: 12.0,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Enter this code in Connector App',
                      style: TextStyle(fontSize: 14, color: Color(0xFF999999)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
