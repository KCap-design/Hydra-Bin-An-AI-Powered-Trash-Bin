import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color _bg      = Color(0xFF0B0E17);
const Color _surface = Color(0xFF131824);
const Color _card    = Color(0xFF1C2030);
const Color _border  = Color(0xFF252B3B);
const Color _accent  = Color(0xFF22C55E);
const Color _textPri = Color(0xFFF8FAFC);
const Color _textSec = Color(0xFF64748B);
const Color _red     = Color(0xFFEF4444);

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

  void _snack(String msg, Color col) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: col,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _connectToHost() async {
    if (_processing) return;

    final code = _codeController.text.trim();
    if (code.length != 6) {
      _snack('Please enter a 6-digit code', _red);
      return;
    }

    setState(() {
      _processing = true;
      _statusMessage = 'Verifying connection...';
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _snack('Session expired. Please log in again.', _red);
        return;
      }

      final sessionDoc = await FirebaseFirestore.instance.collection('sessions').doc(code).get();
      if (!sessionDoc.exists) {
        _snack('Invalid Code. Please check the bin screen.', _red);
        setState(() => _processing = false);
        return;
      }

      final sessionData = sessionDoc.data()!;
      final existingStatus = sessionData['status'] as String?;
      if (existingStatus == 'processing' || existingStatus == 'completed') {
        _snack('Code already in use. Refresh the bin for a new one.', _red);
        setState(() => _processing = false);
        return;
      }

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};
      final name = userData['name'] as String? ?? 'User';
      final points = (userData['points'] as num?)?.toInt() ?? 0;
      final currentStreak = (userData['streak'] as num?)?.toInt() ?? 0;
      final lastConnectionDate = userData['lastConnectionDate'] as Timestamp?;

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
          newStreak = currentStreak;
        }
      }

      setState(() => _statusMessage = 'Connecting to Smart Bin...');

      await FirebaseFirestore.instance.collection('sessions').doc(code).update({
        'status': 'processing',
        'payload': 'User_Logged_In',
        'redeemed': false,
        'connected_user_uid': user.uid,
        'connected_user': {
          'uid': user.uid,
          'name': name,
          'email': user.email ?? '',
          'points': points,
          'connectedAt': FieldValue.serverTimestamp(),
        },
      });

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'activeSession': code,
        'connectedAt': FieldValue.serverTimestamp(),
        'streak': newStreak,
        'lastConnectionDate': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() {
        _waitingForResult = true;
        _waitingSeconds = 0;
        _statusMessage = 'Sorting in progress...\nCheck the bin screen.';
      });

      _startWaitingTimer();
      _listenToSession(code, user.uid);
    } catch (e) {
      _snack('Connection failed: ${e.toString()}', _red);
      if (mounted) setState(() => _processing = false);
    }
  }

  void _listenToSession(String code, String uid) {
    _sessionSubscription = FirebaseFirestore.instance.collection('sessions').doc(code).snapshots().listen((snap) async {
      if (!snap.exists || !mounted) return;
      final data = snap.data()!;
      final status = data['status'] as String? ?? '';

      if (status == 'done' || status == 'completed' || status == 'rewarded' || data['redeemed'] == true) {
        _sessionSubscription?.cancel();
        _waitingTimer?.cancel();

        final pointsAwarded = (data['points_awarded'] as num?)?.toInt() ?? (data['points'] as num?)?.toInt() ?? 10;

        if (data['redeemed'] != true) {
          await FirebaseFirestore.instance.collection('sessions').doc(code).update({'redeemed': true});
          await FirebaseFirestore.instance.collection('users').doc(uid).update({
            'points': FieldValue.increment(pointsAwarded),
            'updatedAt': FieldValue.serverTimestamp(),
            'activeSession': '',
          });
          await FirebaseFirestore.instance.collection('users').doc(uid).collection('recent_activity').add({
            'title': 'Recycle Complete',
            'description': '+$pointsAwarded points added.',
            'points': pointsAwarded,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }

        if (mounted) {
          setState(() => _statusMessage = 'Success! +$pointsAwarded Points earned.');
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) Navigator.of(context).pop();
        }
      }
    });
  }

  void _startWaitingTimer() {
    _waitingTimer?.cancel();
    _waitingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() => _waitingSeconds++);
      if (_waitingSeconds >= 45) { timer.cancel(); _cancelWait(); _snack('Connection timed out', _red); }
    });
  }

  void _cancelWait() {
    _sessionSubscription?.cancel();
    _waitingTimer?.cancel();
    setState(() { _waitingForResult = false; _processing = false; _statusMessage = ''; _waitingSeconds = 0; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(62),
        child: Container(
          decoration: const BoxDecoration(
              color: _surface, border: Border(bottom: BorderSide(color: _border))),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _textPri, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Expanded(
                  child: Text('Smart Bin Connect',
                      style: TextStyle(color: _textPri, fontSize: 17,
                          fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                ),
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _accent.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.sensors_rounded, color: _accent, size: 18),
                ),
              ]),
            ),
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _waitingForResult ? _buildWaitingUI() : _buildConnectUI(),
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingUI() {
    final isDone = _statusMessage.startsWith('Success');
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(24), border: Border.all(color: _border)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (isDone)
          const Icon(Icons.check_circle_rounded, size: 72, color: _accent)
        else
          SizedBox(width: 60, height: 60, child: CircularProgressIndicator(color: _accent, strokeWidth: 4)),
        const SizedBox(height: 24),
        Text(_statusMessage, textAlign: TextAlign.center, style: const TextStyle(color: _textPri, fontSize: 18, fontWeight: FontWeight.bold)),
        if (!isDone) ...[
          const SizedBox(height: 12),
          Text('${45 - _waitingSeconds}s remaining', style: const TextStyle(color: _textSec, fontSize: 13)),
        ],
        if (!isDone && _waitingSeconds >= 20) ...[
          const SizedBox(height: 32),
          GestureDetector(
            onTap: _cancelWait,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
              child: const Center(child: Text('Cancel Connection', style: TextStyle(color: _textPri, fontWeight: FontWeight.w600))),
            ),
          ),
        ]
      ]),
    );
  }

  Widget _buildConnectUI() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: _card, borderRadius: BorderRadius.circular(24), border: Border.all(color: _border),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 40, offset: const Offset(0, 10))],
        ),
        child: Column(children: [
           Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: _border)),
            child: const Icon(Icons.qr_code_2_rounded, color: _textPri, size: 40),
          ),
          const SizedBox(height: 24),
          const Text('Verification Code', style: TextStyle(color: _textPri, fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Enter the 6-digit code shown on the Bin device screen.', textAlign: TextAlign.center, style: TextStyle(color: _textSec, fontSize: 14)),
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
            child: TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _textPri, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 12),
              decoration: const InputDecoration(counterText: '', border: InputBorder.none, hintText: '000000', hintStyle: TextStyle(color: _border)),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),
          const SizedBox(height: 40),
          GestureDetector(
            onTap: _processing ? null : _connectToHost,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: _processing ? _accent.withValues(alpha: 0.5) : _accent,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [if (!_processing) BoxShadow(color: _accent.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 5))],
              ),
              child: Center(child: _processing 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5))
                : const Text('Connect Now', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1))),
            ),
          ),
        ]),
      ),
    ]);
  }
}
