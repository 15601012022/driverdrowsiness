import 'package:tflite_flutter/tflite_flutter.dart';

import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';

class MLModelService {
  late Interpreter eyeInterpreter;
  late Interpreter yawnInterpreter;

  Future<void> loadModel() async {
    try {
      // Add 'assets/' prefix to the path
      eyeInterpreter =
      await Interpreter.fromAsset('assets/model/eye_model.tflite');
      yawnInterpreter =
      await Interpreter.fromAsset('assets/model/yawn_model.tflite');
      print("✅ Both models loaded successfully!");
    } catch (e) {
      print("❌ Error loading models: $e");
      rethrow;
    }
  }

  // For file/JPEG-based camera input
  List<double> preprocessCameraFile(Uint8List bytes) {
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('Image decode failed');
    img.Image resized = img.copyResize(image, width: 160, height: 160);

    List<double> input = [];
    for (int y = 0; y < resized.height; y++) {
      for (int x = 0; x < resized.width; x++) {
        final pixel = resized.getPixel(x, y);
        // Access color channels as double
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();

        input.add(r / 255.0);
        input.add(g / 255.0);
        input.add(b / 255.0);
      }
    }

    print('First 10 input values: ${input.take(10).toList()}');
    print(
        'Min: ${input.reduce((a, b) => a < b ? a : b)}, Max: ${input.reduce((a,
            b) => a > b ? a : b)}');
    return input;
  }

  Future<Map<String, dynamic>> runPrediction(List<double> input) async {
    var inputTensor = Float32List.fromList(input).reshape([1, 160, 160, 3]);
    var eyeOutput = Float32List(2).reshape([1, 2]);
    var yawnOutput = Float32List(2).reshape([1, 2]);
    eyeInterpreter.run(inputTensor, eyeOutput);
    yawnInterpreter.run(inputTensor, yawnOutput);

    print("Eye output = ${eyeOutput[0][0]}, ${eyeOutput[0][1]}");
    print("Yawn output = ${yawnOutput[0][0]}, ${yawnOutput[0][1]}");

    bool eyeClosed = eyeOutput[0][1] > eyeOutput[0][0];
    bool yawnDetected = yawnOutput[0][1] > yawnOutput[0][0];

    return {
      'eye_closed': eyeClosed,
      'yawn_detected': yawnDetected,
      'eye_confidence': eyeOutput[0],
      'yawn_confidence': yawnOutput[0],
    };
  }


  // For CameraImage (YUV) input
  Future<List<double>> preprocessCameraImage(CameraImage cameraImage) async {
    final int width = cameraImage.width;
    final int height = cameraImage.height;

    img.Image rgbImage = img.Image(width: width, height: height);
    // ... populate rgbImage ...

    img.Image resized = img.copyResize(rgbImage, width: 160, height: 160);

    List<double> input = [];
    for (int y = 0; y < resized.height; y++) {
      for (int x = 0; x < resized.width; x++) {
        final pixel = resized.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();

        input.add(r / 255.0);
        input.add(g / 255.0);
        input.add(b / 255.0);
      }
    }

    return input;
  }
}
