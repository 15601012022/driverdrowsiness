import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:tflite_flutter_helper/tflite_flutter_helper.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'package:tflite_flutter_plus/tflite_flutter_plus.dart';


class MLModelService {
  late Interpreter interpreter;

  Future<void> loadModel() async {
    interpreter = await Interpreter.fromAsset('model/model.tflite');
  }

  List<double> preprocessCameraImage(Uint8List bytes) {
    // Decode image
    img.Image? image = img.decodeImage(bytes);

    // Resize to 224x224 (adjust for your model)
    img.Image resized = img.copyResize(image!, width: 224, height: 224);

    // Convert to normalized float list
    List<double> input = [];

    for (int y = 0; y < resized.height; y++) {
      for (int x = 0; x < resized.width; x++) {
        final pixel = resized.getPixel(x, y);

        // Get RGB channels, normalized to 0..1
        input.add(img.getRed(pixel) / 255.0);
        input.add(img.getGreen(pixel) / 255.0);
        input.add(img.getBlue(pixel) / 255.0);
      }
    }

    return input;
  }

  Future<List<dynamic>> runPrediction(List<double> input) async {
    var inputTensor = [input]; // Adjust shape for your model
    var output = List.filled(1 * 1, 0).reshape([1, 1]); // Adjust output shape

    interpreter.run(inputTensor, output);
    return output[0];
  }
}