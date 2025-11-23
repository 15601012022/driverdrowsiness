import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';

class MLModelService {
  late Interpreter eyeInterpreter;
  late Interpreter yawnInterpreter;

  // Load both models with error catching
  Future<void> loadModel() async {
    try {
      eyeInterpreter = await Interpreter.fromAsset('assets/model/eye_model.tflite');
      print('Eye model interpreter loaded: $eyeInterpreter');
    } catch (e) {
      print('Error loading eye model: $e');
      rethrow;
    }
    try {
      yawnInterpreter = await Interpreter.fromAsset('assets/model/yawn_model.tflite');
      print('Yawn model interpreter loaded: $yawnInterpreter');
    } catch (e) {
      print('Error loading yawn model: $e');
      rethrow;
    }
    print("Both models loaded successfully!");
  }

  // Preprocess camera image bytes for TFLite input
  List<double> preprocessCameraImage(Uint8List bytes) {
    img.Image? image = img.decodeImage(bytes);
    if (image == null) {
      print('Image decode error');
      throw Exception('Image decode failed');
    }
    print('Image decoded. Size: ${image.width}x${image.height}');
    img.Image resized = img.copyResize(image, width: 224, height: 224);

    List<double> input = [];

    for (int y = 0; y < resized.height; y++) {
      for (int x = 0; x < resized.width; x++) {
        final pixel = resized.getPixel(x, y);
        input.add(img.getRed(pixel) / 255.0);
        input.add(img.getGreen(pixel) / 255.0);
        input.add(img.getBlue(pixel) / 255.0);
      }
    }

    // Debug: Print tensor values and normalization
    print('Input tensor length: ${input.length}');
    print('First 10 values: ${input.take(10).toList()}');
    double minInput = input.reduce((a, b) => a < b ? a : b);
    double maxInput = input.reduce((a, b) => a > b ? a : b);
    print('Input min: $minInput, max: $maxInput');

    return input;
  }

  // Run inference on both models and parse output
  Future<Map<String, dynamic>> runPrediction(List<double> input) async {
    var inputTensor = Float32List.fromList(input).reshape([1, 224, 224, 3]);

    var eyeOutput = Float32List(2).reshape([1, 2]);
    var yawnOutput = Float32List(2).reshape([1, 2]);

    try {
      eyeInterpreter.run(inputTensor, eyeOutput);
      yawnInterpreter.run(inputTensor, yawnOutput);
    } catch (e) {
      print('Model run error: $e');
      throw Exception('Model run failed');
    }

    // Debug: Print raw outputs
    print('Eye model output: ${eyeOutput[0]}');
    print('Yawn model output: ${yawnOutput[0]}');

    // Output parsing, adjust threshold logic as per training
    bool eyeClosed = eyeOutput[0][1] > eyeOutput[0][0]; // Index 1: closed
    bool yawnDetected = yawnOutput[0][1] > yawnOutput[0][0]; // Index 1: yawn

    return {
      'eye_closed': eyeClosed,
      'yawn_detected': yawnDetected,
      'eye_confidence': eyeOutput[0],
      'yawn_confidence': yawnOutput[0],
    };
  }
}
