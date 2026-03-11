import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hydra_host/services/host_service.dart';
import 'package:hydra_host/services/real_ai_classifier.dart';
import 'package:hydra_host/screens/host_screen.dart';
import 'package:hydra_host/services/mqtt_service.dart';

class AIProcessingScreen extends StatefulWidget {
  final String scannedContent;
  final Map<String, dynamic> userInfo;
  final DocumentSnapshot sessionSnapshot;
  final dynamic hostService;

  const AIProcessingScreen({
    super.key,
    required this.scannedContent,
    required this.userInfo,
    required this.sessionSnapshot,
    required this.hostService,
  });

  @override
  State<AIProcessingScreen> createState() => _AIProcessingScreenState();
}

class _AIProcessingScreenState extends State<AIProcessingScreen> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  String _currentPrediction = 'Initializing...';
  double _currentConfidence = 0.0;
  int _processingTime = 0;
  Timer? _processingTimer;
  Timer? _cameraTimer;
  final List<ClassificationResult> _predictionHistory = [];
  DateTime? _lastProcessingTime;
  DateTime? _sessionStartTime;
  DateTime? _holdStillStartTime;

  // AI Processing settings
  static const int cameraInterval = 150; // ms
  static const int maxProcessingTime = 60; // seconds global timer
  static const int requiredFrames = 20; // 20 frames
  static const double confidenceThreshold = 0.90; // 90% confidence

  // Mock labels
  final List<String> _labels = [
    'background',
    'biodegradable',
    'landfills',
    'recyclable'
  ];

  @override
  void initState() {
    super.initState();
    _sessionStartTime = DateTime.now();
    _initializeCamera();
    _startProcessingTimer();
    
    // Initialize MQTT
    MqttService().initializeMqttClient();
  }

  Future<void> _initializeCamera() async {
    try {
      // Request camera permission
      final cameraPermission = await Permission.camera.request();
      if (!cameraPermission.isGranted) {
        _showError('Camera permission denied');
        return;
      }

      // Initialize REAL AI Classifier
      await RealAIClassifier.initialize();

      // Get available cameras
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _showError('No cameras available');
        return;
      }

      // Use back camera
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // Initialize camera controller
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _currentPrediction = 'REAL AI Scanning for trash...';
        });

        // Start REAL camera frame processing
        _startCameraProcessing();
      }
    } catch (e) {
      print('Camera initialization error: $e');
      _showError('Failed to initialize camera: $e');
    }
  }

  void _startCameraProcessing() {
    _cameraController!.startImageStream((cameraImage) {
      if (!_isProcessing && mounted) {
        final now = DateTime.now();
        if (_lastProcessingTime != null && now.difference(_lastProcessingTime!).inMilliseconds < cameraInterval) {
          return;
        }
        _lastProcessingTime = now;

        final result = RealAIClassifier.classifyImage(cameraImage);
        if (result != null && mounted) {
          _handleClassificationResult(result, now);
        }
      }
    });
  }

  void _handleClassificationResult(ClassificationResult result, DateTime now) {
    if (_sessionStartTime == null) return;
    
    final elapsedSessionSeconds = now.difference(_sessionStartTime!).inSeconds;
    
    // 1. 3-second grace period ignoring Background
    if (elapsedSessionSeconds < 3 && result.label == 'background') {
      setState(() {
        _currentPrediction = 'Position item in frame...';
        _currentConfidence = 0.0;
        _predictionHistory.clear();
      });
      return;
    }

    // 2. Hold Still logic (50% - 89% for > 3 seconds)
    if (result.confidence >= 0.50 && result.confidence < confidenceThreshold) {
      _holdStillStartTime ??= now;
      if (now.difference(_holdStillStartTime!).inSeconds >= 3) {
        setState(() {
          _currentPrediction = 'Hold Still: Analyzing...';
          _currentConfidence = result.confidence;
        });
      } else {
        setState(() {
          _currentPrediction = result.label;
          _currentConfidence = result.confidence;
        });
      }
    } else {
      _holdStillStartTime = null; 
      setState(() {
        _currentPrediction = result.label;
        _currentConfidence = result.confidence;
      });
    }

    // 3. Track Confirmations
    if (result.confidence >= confidenceThreshold) {
      setState(() {
        if (_predictionHistory.isNotEmpty && _predictionHistory.last.label != result.label) {
          _predictionHistory.clear();
        }
        _predictionHistory.add(result);
        if (_predictionHistory.length > requiredFrames) {
          _predictionHistory.removeAt(0);
        }
      });
      
      if (_predictionHistory.length == requiredFrames) {
        bool allSame = _predictionHistory.every((r) => r.label == result.label);
        if (allSame) {
          _handleConfirmedLabel(result.label);
        }
      }
    } else {
      setState(() {
        _predictionHistory.clear();
      });
    }
  }

  void _handleConfirmedLabel(String label) {
    if (_isProcessing) return;
    
    _isProcessing = true;
    _cameraTimer?.cancel();
    _processingTimer?.cancel();
    _cameraController?.stopImageStream();
    
    if (label == 'background') {
      setState(() {
        _currentPrediction = 'No item detected. Returning to home...';
      });
      _resetSystemWithoutPoint();
    } else if (['biodegradable', 'landfills', 'recyclable'].contains(label)) {
      setState(() {
        _currentPrediction = 'Confirmed: $label! Awarding points...';
      });

      // Send the classification result via MQTT
      MqttService().publishMessage(label);

      _awardPointsAndResetSystem();
    }
  }

  void _resetSystemWithoutPoint() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HostScreen()),
          (route) => false,
        );
      }
    });
  }

  void _awardPointsAndResetSystem() async {
    try {
      String? connectedUserId = widget.userInfo['uid'] ?? widget.userInfo['id'];
      if (connectedUserId == null || connectedUserId.isEmpty) {
        connectedUserId = HostService.getConnectedUserId(widget.sessionSnapshot);
      }

      print('AI REWARD: Attempting to award points to user: $connectedUserId');

      if (connectedUserId != null && connectedUserId.isNotEmpty) {
        await HostService.awardPointsToUserById(connectedUserId);
      } else {
        print('AI REWARD ERROR: No valid user ID found to award points to.');
      }
      await HostService.markSessionAsRedeemed(widget.sessionSnapshot);

      setState(() {
        _currentPrediction = '✅ Points awarded! Returning to home...';
      });

      _resetSystemWithoutPoint();
    } catch (e) {
      _showError('Failed to complete transaction: $e');
    }
  }

  void _startProcessingTimer() {
    _processingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _isProcessing) {
        timer.cancel();
        return;
      }
      if (_sessionStartTime != null) {
        final elapsed = DateTime.now().difference(_sessionStartTime!).inSeconds;
        setState(() {
          _processingTime = elapsed;
        });

        if (elapsed >= maxProcessingTime) {
          print('⏰ Max processing time reached');
          _timeoutAndReset();
        }
      }
    });
  }

  void _timeoutAndReset() {
    _isProcessing = true;
    _processingTimer?.cancel();
    _cameraTimer?.cancel();
    _cameraController?.stopImageStream();

    setState(() {
      _currentPrediction = 'Session Timeout...';
    });

    _resetSystemWithoutPoint();
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );

      // Return to home after error
      Future.delayed(Duration(seconds: 3), () {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HostScreen()),
            (route) => false,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _processingTimer?.cancel();
    _cameraTimer?.cancel();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    RealAIClassifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF2C2C2C),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    '🤖 TRASH SCANNER',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Point camera at trash item',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatusChip(
                          'Time', '$_processingTime s', Colors.blue),
                      _buildStatusChip(
                          'Frames',
                          '${_predictionHistory.length}/$requiredFrames',
                          Colors.orange),
                    ],
                  ),
                ],
              ),
            ),

            // Camera View
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Stack(
                  children: [
                    // Camera preview
                    if (_isCameraInitialized && _cameraController != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: CameraPreview(_cameraController!),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                          ),
                        ),
                      ),

                    // Overlay info
                    Positioned(
                      bottom: 20,
                      left: 20,
                      right: 20,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _currentPrediction,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (_currentConfidence > 0) ...[
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: _currentConfidence,
                                backgroundColor: Colors.grey[600],
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _currentConfidence >= 0.9
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Confidence: ${(_currentConfidence * 100).toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[300],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // Scanning overlay
                    if (_isCameraInitialized && !_isProcessing)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.green.withOpacity(0.5),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Instructions
            Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'Instructions:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Show biodegradable, recyclable, or landfill items\n'
                    '• Hold steady for 20 consistent detections (90%+ confidence)\n'
                    '• Background will reset the scanner\n'
                    '• 60 second timeout limit',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[400],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.8),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

