import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';



class MLModelService {
  late Interpreter interpreter;

  Future<void> loadModel() async {
    interpreter = await Interpreter.fromAsset('model/model.tflite');
  }


  List<double> preprocessCameraImage(Uint8List bytes) {
    final image = img.decodeImage(bytes)!;
    final resized = img.copyResize(image, width: 224, height: 224); // Adjust for your model

    final input = <double>[];

    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final pixel = resized.getPixel(x, y);
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