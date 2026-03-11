import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hydra_host/screens/host_screen.dart';


class ProcessingScreen extends StatefulWidget {
  final String scannedContent;
  final Map<String, dynamic> userInfo;
  final DocumentSnapshot sessionSnapshot;
  final dynamic hostService;

  const ProcessingScreen({
    super.key,
    required this.scannedContent,
    required this.userInfo,
    required this.sessionSnapshot,
    required this.hostService,
  });

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen>
    with TickerProviderStateMixin {
  static const int processingDuration = 10; // seconds
  double _progress = 0.0;
  int _remainingSeconds = processingDuration;
  Timer? _timer;

  late AnimationController _progressController;
  late AnimationController _fadeController;
  late Animation<double> _progressAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startProcessing();
    _startFadeInAnimation();
  }

  void _setupAnimations() {
    _progressController = AnimationController(
      duration: const Duration(seconds: processingDuration),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _progressController, curve: Curves.linear));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _fadeController, curve: Curves.easeIn));

    _progressController.addListener(() {
      if (mounted) {
        setState(() {
          _progress = _progressAnimation.value;
          _remainingSeconds =
              processingDuration - (_progress * processingDuration).round();
        });
      }
    });
  }

  void _startFadeInAnimation() {
    _fadeController.forward();
  }

  void _startProcessing() {
    _progressController.forward();

    // Update countdown every second
    for (int i = processingDuration; i > 0; i--) {
      Future.delayed(Duration(seconds: processingDuration - i), () {
        if (mounted) {
          setState(() {
            _remainingSeconds = i;
          });
        }
      });
    }

    // Complete processing after duration
    Future.delayed(const Duration(seconds: processingDuration), () {
      if (mounted) {
        _completeProcessing();
      }
    });
  }

  void _completeProcessing() {
    // Award points to user AFTER processing completes
    final connectedUserId =
        widget.hostService.getConnectedUserId(widget.sessionSnapshot);
    if (connectedUserId != null && connectedUserId.isNotEmpty) {
      print('PROCESSING COMPLETE: Awarding points to user: $connectedUserId');
      widget.hostService.awardPointsToUserById(connectedUserId);
      print('PROCESSING COMPLETE: Points awarded successfully!');
    } else {
      print('PROCESSING COMPLETE ERROR: No connected user ID found');
    }

    // Update session status to completed
    _updateSessionStatus();

    // Return to home screen
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HostScreen()),
          (route) => false,
        );
      }
    });
  }

  void _updateSessionStatus() async {
    try {
      final sessionRef = widget.sessionSnapshot.reference;
      await sessionRef.update({
        'status': 'completed',
        'updated_at': FieldValue.serverTimestamp(),
      });
      print('Session marked as completed');
    } catch (e) {
      print('Error updating session status: $e');
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _progressController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D44),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _remainingSeconds > 0
                            ? Icons.hourglass_top
                            : Icons.check_circle,
                        color: _remainingSeconds > 0
                            ? Colors.orange
                            : Colors.green,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _remainingSeconds > 0
                            ? 'PROCESSING...'
                            : 'PROCESSING COMPLETE!',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _remainingSeconds > 0
                            ? 'Please wait while we process your connection'
                            : 'Points awarded successfully',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 48),

                // Progress indicator with big countdown
                Column(
                  children: [
                    // Big countdown number
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: _remainingSeconds > 0
                            ? Colors.orange.withOpacity(0.2)
                            : Colors.green.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _remainingSeconds > 0
                              ? Colors.orange
                              : Colors.green,
                          width: 3,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$_remainingSeconds',
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: _remainingSeconds > 0
                                ? Colors.orange
                                : Colors.green,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: Colors.grey[700],
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.green),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _remainingSeconds > 0
                          ? 'Time remaining: $_remainingSeconds seconds'
                          : 'Processing complete!',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 48),

                // Connection info
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'CONNECTION DETAILS',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.scannedContent.length > 30
                            ? '${widget.scannedContent.substring(0, 30)}...'
                            : widget.scannedContent,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () =>
                            Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (context) => const HostScreen(),
                          ),
                          (route) => false,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D2D44),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        child: const Text('RETURN TO HOME'),
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
