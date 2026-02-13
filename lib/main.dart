import 'dart:io';
import 'dart:convert';
import 'package:app_feijao/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Main widget for the image predictor application
class ImagePredictorApp extends StatefulWidget {
  @override
  _ImagePredictorAppState createState() => _ImagePredictorAppState();
}

/// State class for the ImagePredictorApp widget
class _ImagePredictorAppState extends State<ImagePredictorApp> {
  // List to store processed images with their LAB color values
  final List<Map<String, dynamic>> _processedImages = [];
  // Image picker instance for selecting images from camera or gallery
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadProcessedImages();
  }

  /// Picks an image from the specified source (camera or gallery)
  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);

    if (pickedFile == null) {
      print("No image selected.");
      return;
    }

    final File image = File(pickedFile.path);

    if (!await image.exists()) {
      print("Error: Image file not found.");
      return;
    }

    // Process the selected image with the ML models
    final predictions = await _processImage(image);

    if (predictions != null) {
      setState(() {
        _processedImages.add({
          'image': image,
          'L': predictions['L'],
          'a': predictions['a'],
          'b': predictions['b'],
        });
      });
      _saveProcessedImages();
    }
  }

  /// Saves the processed images to local storage using SharedPreferences
  Future<void> _saveProcessedImages() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _processedImages
        .map((item) => {
              'path': item['image'].path,
              'L': item['L'],
              'a': item['a'],
              'b': item['b'],
            })
        .toList();
    await prefs.setString('processed_images', jsonEncode(data));
  }

  /// Loads previously processed images from local storage
  Future<void> _loadProcessedImages() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('processed_images');
    if (data != null) {
      setState(() {
        _processedImages.clear();
        _processedImages.addAll(
          List<Map<String, dynamic>>.from(jsonDecode(data)).map((item) => {
                'image': File(item['path']),
                'L': item['L'],
                'a': item['a'],
                'b': item['b'],
              }),
        );
      });
    }
  }

  /// Processes the image using three separate TFLite models (L, a, b)
  Future<Map<String, String>?> _processImage(File image) async {
    Interpreter? interpreterL;
    Interpreter? interpreterA;
    Interpreter? interpreterB;
    try {
      // Load the three models for LAB color space prediction
      interpreterL = await Interpreter.fromAsset('assets/models/modelL.tflite');
      interpreterA = await Interpreter.fromAsset('assets/models/modela.tflite');
      interpreterB = await Interpreter.fromAsset('assets/models/modelb.tflite');

      // Preprocess the image to the required input format
      final input = await _preprocessImage(image);

      // Initialize output tensors
      var outputL = List.filled(1, List.filled(1, 0.0));
      var outputA = List.filled(1, List.filled(1, 0.0));
      var outputB = List.filled(1, List.filled(1, 0.0));

      // Run the models and get predictions
      interpreterL.run(input, outputL);
      interpreterA.run(input, outputA);
      interpreterB.run(input, outputB);

      return {
        'L': outputL[0][0].toStringAsFixed(2),
        'a': outputA[0][0].toStringAsFixed(2),
        'b': outputB[0][0].toStringAsFixed(2),
      };
    } catch (e) {
      print('Error processing image: $e');
      return null;
    } finally {
      // Close the interpreters to free resources
      interpreterL?.close();
      interpreterA?.close();
      interpreterB?.close();
    }
  }

  /// Preprocesses the image: decodes, resizes, and normalizes to model input format
  Future<List<List<List<List<double>>>>> _preprocessImage(File image) async {
    try {
      // Read image bytes and decode
      final imageBytes = await image.readAsBytes();
      final img.Image? originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) {
        throw Exception("Error decoding image.");
      }
      // Resize image to 224x224 as required by the models
      final img.Image resizedImage =
          img.copyResize(originalImage, width: 224, height: 224);
      // Normalize pixel values to [0, 1] range
      final input = List.generate(
        1,
        (batch) => List.generate(
          224,
          (height) => List.generate(
            224,
            (width) {
              final pixel = resizedImage.getPixelSafe(width, height);
              final r = ((pixel >> 16) & 0xFF) / 255.0;
              final g = ((pixel >> 8) & 0xFF) / 255.0;
              final b = (pixel & 0xFF) / 255.0;
              return [r, g, b];
            },
          ),
        ),
      );
      return input;
    } catch (e) {
      print('Error preprocessing image: $e');
      rethrow;
    }
  }

  /// Deletes an image from the list
  void _deleteImage(int index) {
    setState(() {
      _processedImages.removeAt(index);
    });
    _saveProcessedImages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ALIZAROL', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 221, 124, 107),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: _processedImages.isEmpty
            ? Center(child: Text('Nenhuma imagem selecionada até o momento'))
            : ListView.builder(
                itemCount: _processedImages.length,
                itemBuilder: (context, index) {
                  final item = _processedImages[index];
                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 8),
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              // Image thumbnail
                              Container(
                                width: 100,
                                height: 100,
                                child: Image.file(
                                  item['image'],
                                  fit: BoxFit.cover,
                                ),
                              ),
                              SizedBox(width: 16),
                              // LAB color values display
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('L: ${item['L']}',
                                        style: TextStyle(fontSize: 18)),
                                    Text('a: ${item['a']}',
                                        style: TextStyle(fontSize: 18)),
                                    Text('b: ${item['b']}',
                                        style: TextStyle(fontSize: 18)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Delete button
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton(
                            icon: Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteImage(index),
                            iconSize: 24,
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints(),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      // Floating action button to add new images
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            builder: (BuildContext context) {
              return Wrap(
                children: [
                  // Camera option
                  ListTile(
                    leading: Icon(Icons.camera_alt),
                    title: Text('Take Photo'),
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                  // Gallery option
                  ListTile(
                    leading: Icon(Icons.image),
                    title: Text('Choose from Gallery'),
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                ],
              );
            },
          );
        },
        backgroundColor: Colors.blue,
        child: Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// Entry point of the application
void main() => runApp(MyApp());

/// Main app widget that sets up the MaterialApp and navigation
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'L*a*b*',
      locale: Locale('en'),
      supportedLocales: [Locale('en')],
      home: SplashScreen(),
    );
  }
}
