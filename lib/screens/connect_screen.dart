import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final TextEditingController _codeController = TextEditingController();
  StreamSubscription<DocumentSnapshot>? _sessionSubscription;

  bool _processing = false;
  bool _waitingForResult = false;
  String _statusMessage = '';
  Timer? _waitingTimer;
  int _waitingSeconds = 0;

  @override
  void dispose() {
    _codeController.dispose();
    _sessionSubscription?.cancel();
    _waitingTimer?.cancel();
    super.dispose();
  }

  Future<void> _connectToHost() async {
    if (_processing) return;

    final code = _codeController.text.trim();

    if (code.length != 6) {
      _showError('Please enter a 6-digit code');
      return;
    }

    setState(() {
      _processing = true;
      _statusMessage = 'Checking code...';
    });

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        _showError('You must be logged in');
        return;
      }

      // Check if session exists
      final sessionDoc = await FirebaseFirestore.instance
          .collection('sessions')
          .doc(code)
          .get();

      if (!sessionDoc.exists) {
        _showError('Invalid Code');
        return;
      }

      // Check if session is already taken
      final sessionData = sessionDoc.data()!;
      final existingStatus = sessionData['status'] as String?;
      if (existingStatus == 'processing' || existingStatus == 'completed') {
        _showError('This code is already in use. Please get a new code.');
        return;
      }

      // Get user data
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final name = userDoc.data()?['name'] as String? ?? 'Anonymous';
      final points = (userDoc.data()?['points'] as num?)?.toInt() ?? 0;
      final currentStreak = (userDoc.data()?['streak'] as num?)?.toInt() ?? 0;
      final lastConnectionDate =
          userDoc.data()?['lastConnectionDate'] as Timestamp?;

      int newStreak = 1;
      final now = DateTime.now();

      if (lastConnectionDate != null) {
        final last = lastConnectionDate.toDate();
        final diff = DateTime(now.year, now.month, now.day)
            .difference(DateTime(last.year, last.month, last.day))
            .inDays;

        if (diff == 1) {
          newStreak = currentStreak + 1;
        } else if (diff == 0) {
          newStreak = currentStreak; // already connected today
        } else {
          newStreak = 1; // streak broken
        }
      }

      setState(() => _statusMessage = 'Connecting to Smart Bin...');

      // Update session document — triggers host to start processing
      await FirebaseFirestore.instance.collection('sessions').doc(code).update({
        'status': 'processing',
        'payload': 'User_Logged_In',
        'redeemed': false,
        'connected_user_uid': user.uid,
        'connected_user': {
          'uid': user.uid,
          'name': name,
          'email': user.email ?? '',
          'isAnonymous': user.isAnonymous,
          'points': points,
          'connectedAt': FieldValue.serverTimestamp(),
        },
      });

      // Update user's active session + streak
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {
          'activeSession': code,
          'connectedAt': FieldValue.serverTimestamp(),
          'streak': newStreak,
          'lastConnectionDate': FieldValue.serverTimestamp(),
        },
      );

      if (!mounted) return;

      setState(() {
        _waitingForResult = true;
        _waitingSeconds = 0;
        _statusMessage =
            'Connected! Waiting for host to sort trash...\nPlease sort your trash on the device.';
      });

      // Start the timeout timer
      _startWaitingTimer();

      // Now listen to the session document for result
      _listenToSession(code, user.uid);
    } catch (e) {
      debugPrint('Connection error: $e');
      _showError('Connection failed: ${e.toString()}');
      if (mounted) setState(() => _processing = false);
    }
  }

  /// Listens to the session document. When the host finishes (status == 'done'
  /// or 'completed'), awards points to the user directly from Flutter.
  void _listenToSession(String code, String uid) {
    _sessionSubscription = FirebaseFirestore.instance
        .collection('sessions')
        .doc(code)
        .snapshots()
        .listen(
          (snap) async {
            if (!snap.exists || !mounted) return;

            final data = snap.data()!;
            final status = data['status'] as String? ?? '';
            debugPrint('Session status: $status');

            // Host marks session as done/completed after sorting
            if (status == 'done' ||
                status == 'completed' ||
                status == 'rewarded' ||
                data['redeemed'] == true) {
              _sessionSubscription?.cancel();
              _waitingTimer?.cancel();

              // Read how many points the host awarded (default 1)
              final pointsAwarded =
                  (data['points_awarded'] as num?)?.toInt() ??
                  (data['pointsAwarded'] as num?)?.toInt() ??
                  (data['points'] as num?)?.toInt() ??
                  1;

              // Award points to user from Flutter side (safe even if host also did it)
              try {
                final alreadyRedeemed = data['redeemed'] as bool? ?? false;

                if (!alreadyRedeemed) {
                  // Mark redeemed first to prevent double-award
                  await FirebaseFirestore.instance
                      .collection('sessions')
                      .doc(code)
                      .update({'redeemed': true});

                  // Award points to user
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .update({
                    'points': FieldValue.increment(pointsAwarded),
                    'updatedAt': FieldValue.serverTimestamp(),
                    'activeSession': '',
                  });

                  // Log to recent_activity
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('recent_activity')
                      .add({
                    'title': 'Recycle Complete',
                    'description':
                        'Recycle complete! +$pointsAwarded point${pointsAwarded == 1 ? '' : 's'} added to your account.',
                    'points': pointsAwarded,
                    'timestamp': FieldValue.serverTimestamp(),
                  });

                  if (mounted) {
                    setState(() {
                      _statusMessage = '✅ Recycle complete! +$pointsAwarded point${pointsAwarded == 1 ? '' : 's'} earned!';
                    });

                    // Wait a moment then go back
                    await Future.delayed(const Duration(seconds: 2));
                    if (mounted) Navigator.of(context).pop();
                  }
                } else {
                  // Already redeemed by host, still navigate back
                  if (mounted) {
                    setState(() {
                      _statusMessage = '✅ Points already awarded!';
                    });
                    await Future.delayed(const Duration(seconds: 2));
                    if (mounted) Navigator.of(context).pop();
                  }
                }
              } catch (e) {
                debugPrint('Error awarding points: $e');
                if (mounted) {
                  _showError('Error awarding points: $e');
                  setState(() {
                    _waitingForResult = false;
                    _processing = false;
                  });
                }
              }
            } else if (status == 'error' || status == 'failed') {
              _sessionSubscription?.cancel();
              _waitingTimer?.cancel();
              if (mounted) {
                _showError('Host reported an error. Please try again.');
                setState(() {
                  _waitingForResult = false;
                  _processing = false;
                  _statusMessage = '';
                });
              }
            }
          },
          onError: (e) {
            debugPrint('Session listener error: $e');
            _waitingTimer?.cancel();
            if (mounted) {
              _showError('Lost connection to session: $e');
              setState(() {
                _waitingForResult = false;
                _processing = false;
              });
            }
          },
        );
  }

  void _startWaitingTimer() {
    _waitingTimer?.cancel();
    _waitingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _waitingSeconds++;
      });

      if (_waitingSeconds >= 40) {
        timer.cancel();
        _cancelWait();
        _showError('Connection timed out after 40 seconds.');
      }
    });
  }

  void _cancelWait() {
    _sessionSubscription?.cancel();
    _waitingTimer?.cancel();
    setState(() {
      _waitingForResult = false;
      _processing = false;
      _statusMessage = '';
      _waitingSeconds = 0;
    });
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect to Smart Bin')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: _waitingForResult ? _buildWaitingUI() : _buildConnectUI(),
      ),
    );
  }

  /// Shown while waiting for the host to finish sorting
  Widget _buildWaitingUI() {
    final isDone = _statusMessage.startsWith('✅');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isDone)
          const Icon(Icons.check_circle, size: 80, color: Colors.green)
        else
          const Center(child: CircularProgressIndicator(strokeWidth: 6)),
        const SizedBox(height: 32),
        Text(
          _statusMessage,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: isDone ? Colors.green : null,
          ),
        ),
        if (!isDone && _waitingSeconds >= 20) ...[
          const SizedBox(height: 32),
          const Text(
            'Taking longer than expected...',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
               _cancelWait();
               Navigator.of(context).pop();
            },
            icon: const Icon(Icons.home),
            label: const Text('Return to Home'),
          ),
        ]
      ],
    );
  }

  /// The default code-entry UI
  Widget _buildConnectUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.recycling, size: 80, color: Colors.blueGrey.shade700),
        const SizedBox(height: 32),
        const Text(
          'Enter Bin Connection Code',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        const Text(
          'Enter the 6-digit code displayed on the trash sorter screen',
          style: TextStyle(fontSize: 16, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 48),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            letterSpacing: 8,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.blueGrey, width: 3),
            ),
            hintText: '000000',
            hintStyle: TextStyle(color: Colors.grey[400], letterSpacing: 8),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _processing ? null : _connectToHost,
          icon: _processing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.link),
          label: Text(
            _processing && !_waitingForResult ? 'Connecting...' : 'Connect',
          ),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor:
                _processing ? Colors.grey : Colors.blueGrey.shade800,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.cancel),
          label: const Text('Cancel'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }
}
