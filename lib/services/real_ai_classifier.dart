
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';

class RealAIClassifier {
  static Interpreter? _interpreter;
  static List<String>? _labels;
  static bool _isInitialized = false;

  static const double confidenceThreshold = 0.90;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('🤖 Initializing REAL AI Classifier...');
      final modelData = await rootBundle.load('assets/model/model.tflite');
      final modelBytes = modelData.buffer.asUint8List();
      _interpreter = Interpreter.fromBuffer(modelBytes);
      print('✅ TensorFlow Lite model loaded successfully!');

      final labelsData = await rootBundle.loadString('assets/model/labels.txt');
      _labels = labelsData
          .split('\n')
          .where((label) => label.trim().isNotEmpty)
          .map((label) {
            final parts = label.trim().split(' ');
            if (parts.length > 1 && int.tryParse(parts[0]) != null) {
               return parts.sublist(1).join(' ').trim();
            }
            return label.trim();
          })
          .toList();
      print('📋 Cleaned Labels loaded: $_labels');

      _isInitialized = true;
      print('🎉 REAL AI Classifier initialized successfully!');
    } catch (e) {
      print('❌ Failed to initialize REAL AI Classifier: $e');
      rethrow;
    }
  }

  static ClassificationResult? classifyImage(CameraImage cameraImage) {
    if (!_isInitialized || _interpreter == null || _labels == null) {
      return ClassificationResult('Error: Not Initialized', 0.0);
    }

    try {
      final inputTensor = _interpreter!.getInputTensor(0);
      final shape = inputTensor.shape; 
      final height = shape.length > 1 ? shape[1] : 224;
      final width = shape.length > 2 ? shape[2] : 224;
      final isFloat = inputTensor.type == TensorType.float32;

      final rawInput = _preprocessImage(cameraImage, width, height);

      var input = List.generate(1, (i) => List.generate(height, (y) => List.generate(width, (x) => List.generate(3, (c) {
          int offset = (y * width + x) * 3 + c;
          if (isFloat) {
             return (rawInput[offset] - 127.5) / 127.5;
          } else {
             return rawInput[offset];
          }
      }))));

      final outputTensor = _interpreter!.getOutputTensor(0);
      final isOutputFloat = outputTensor.type == TensorType.float32;
      
      Object output;
      if (isOutputFloat) {
         output = List.generate(1, (_) => List.filled(_labels!.length, 0.0));
      } else {
         output = List.generate(1, (_) => List.filled(_labels!.length, 0));
      }

      _interpreter!.run(input, output);

      List<double> probabilities = [];
      if (output is List<List<double>>) {
         probabilities = output[0];
      } else if (output is List<List<int>>) {
         probabilities = output[0].map((e) => e / 255.0).toList();
      } else {
         probabilities = List.filled(_labels!.length, 0.0);
      }

      return _processOutput(probabilities);
    } catch (e) {
      print('❌ REAL Classification error: $e');
      return ClassificationResult('Err: ${e.toString().split('\n')[0]}', 0.0);
    }
  }

  static Uint8List _preprocessImage(CameraImage cameraImage, int targetWidth, int targetHeight) {
    final imageWidth = cameraImage.width;
    final imageHeight = cameraImage.height;
    
    if (cameraImage.planes.isEmpty) {
       return Uint8List(targetWidth * targetHeight * 3);
    }
    
    final plane = cameraImage.planes[0];
    final inputSize = targetWidth * targetHeight * 3;
    final input = Uint8List(inputSize);
    
    for (int y = 0; y < targetHeight; y++) {
      for (int x = 0; x < targetWidth; x++) {
        final srcX = (x * imageWidth / targetWidth).floor();
        final srcY = (y * imageHeight / targetHeight).floor();
        
        if (srcX < imageWidth && srcY < imageHeight) {
          final srcIndex = srcY * plane.bytesPerRow + srcX * (plane.bytesPerPixel ?? 1);
          if (srcIndex < plane.bytes.length) {
            final yValue = plane.bytes[srcIndex];
            
            final pixelIndex = (y * targetWidth + x) * 3;
            input[pixelIndex] = yValue;     
            input[pixelIndex + 1] = yValue;   
            input[pixelIndex + 2] = yValue; 
          }
        }
      }
    }
    return input;
  }

  static ClassificationResult _processOutput(List<double> output) {
    double maxConfidence = 0.0;
    int maxIndex = 0;

    for (int i = 0; i < output.length; i++) {
      if (output[i] > maxConfidence) {
        maxConfidence = output[i];
        maxIndex = i;
      }
    }

    final label = _labels != null && maxIndex < _labels!.length ? _labels![maxIndex] : 'Unknown';
    return ClassificationResult(label, maxConfidence);
  }

  static void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _labels = null;
    _isInitialized = false;
  }
}

class ClassificationResult {
  final String label;
  final double confidence;

  ClassificationResult(this.label, this.confidence);
}

