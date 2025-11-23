import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';

class MLModelService {
  late Interpreter eyeInterpreter;
  late Interpreter yawnInterpreter;

  Future<void> loadModel() async {
    // Load both models
    eyeInterpreter = await Interpreter.fromAsset('assets/model/eye_model.tflite');
    yawnInterpreter = await Interpreter.fromAsset('assets/model/yawn_model.tflite');
    print("Both models loaded successfully!");
  }

  List<double> preprocessCameraImage(Uint8List bytes) {
    img.Image? image = img.decodeImage(bytes);
    img.Image resized = img.copyResize(image!, width: 224, height: 224);

    List<double> input = [];

    for (int y = 0; y < resized.height; y++) {
      for (int x = 0; x < resized.width; x++) {
        final pixel = resized.getPixel(x, y);
        input.add(img.getRed(pixel) / 255.0);
        input.add(img.getGreen(pixel) / 255.0);
        input.add(img.getBlue(pixel) / 255.0);
      }
    }

    return input;
  }

  Future<Map<String, dynamic>> runPrediction(List<double> input) async {
    // Reshape input for both models
    var inputTensor = input.reshape([1, 224, 224, 3]);

    // Output for eye model (2 classes: open/closed)
    var eyeOutput = List.filled(1 * 2, 0.0).reshape([1, 2]);

    // Output for yawn model (2 classes: yawn/no-yawn)
    var yawnOutput = List.filled(1 * 2, 0.0).reshape([1, 2]);

    // Run both predictions
    eyeInterpreter.run(inputTensor, eyeOutput);
    yawnInterpreter.run(inputTensor, yawnOutput);

    return {
      'eye_closed': eyeOutput[0][1] > eyeOutput[0][0], // Index 1 = closed
      'yawn_detected': yawnOutput[0][1] > yawnOutput[0][0], // Index 1 = yawn
      'eye_confidence': eyeOutput[0],
      'yawn_confidence': yawnOutput[0],
    };
  }
}
