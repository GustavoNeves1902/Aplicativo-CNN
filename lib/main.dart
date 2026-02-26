import 'dart:io';
import 'dart:convert';
import 'package:app_feijao/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_feijao/camera_screen.dart';

/// Main widget for the image predictor application
class ImagePredictorApp extends StatefulWidget {
  @override
  _ImagePredictorAppState createState() => _ImagePredictorAppState();
}

/// State class for the ImagePredictorApp widget
class _ImagePredictorAppState extends State<ImagePredictorApp> {
  // List to store processed images with their results
  final List<Map<String, dynamic>> _processedImages = [];
  // Image picker instance for selecting images from gallery
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadProcessedImages();
  }

  /// Centraliza o processamento da imagem e atualização da UI
  Future<void> _handleProcessedImage(File image) async {
    final predictions = await _processImage(image);

    if (predictions != null) {
      print("Imagem processada com sucesso: ${predictions['resultado']}");
      setState(() {
        _processedImages.add({
          'image': image,
          'resultado': predictions['resultado'],
          'L': predictions['L'],
          'a': predictions['a'],
          'b': predictions['b'],
        });
      });
      _saveProcessedImages();
    } else {
      print("Erro: O processamento retornou nulo.");
    }
  }

  /// Escolhe imagem da Galeria
  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile == null) return;

    final File image = File(pickedFile.path);
    await _handleProcessedImage(image);
  }

  /// Abre a tela de câmera customizada com validação
  Future<void> _captureWithCustomCamera() async {
    final String? imagePath = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(
          onImageCaptured: (path) => path,
        ),
      ),
    );

    if (imagePath != null && imagePath.isNotEmpty) {
      await _handleProcessedImage(File(imagePath));
    }
  }

  /// Salva os dados no SharedPreferences
  Future<void> _saveProcessedImages() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _processedImages
        .map((item) => {
              'path': item['image'].path,
              'resultado': item['resultado'],
              'L': item['L'],
              'a': item['a'],
              'b': item['b'],
            })
        .toList();
    await prefs.setString('processed_images', jsonEncode(data));
  }

  /// Carrega os dados do SharedPreferences
  Future<void> _loadProcessedImages() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('processed_images');
    if (data != null) {
      setState(() {
        _processedImages.clear();
        _processedImages.addAll(
          List<Map<String, dynamic>>.from(jsonDecode(data)).map((item) => {
                'image': File(item['path']),
                'resultado': item['resultado'] ?? 'Sem resultado',
                'L': item['L'],
                'a': item['a'],
                'b': item['b'],
              }),
        );
      });
    }
  }

  /// Processa a imagem usando os modelos TFLite
  Future<Map<String, String>?> _processImage(File image) async {
    Interpreter? interpreterL;
    Interpreter? interpreterA;
    Interpreter? interpreterB;
    try {
      interpreterL = await Interpreter.fromAsset('assets/models/modelL.tflite');
      interpreterA = await Interpreter.fromAsset('assets/models/modela.tflite');
      interpreterB = await Interpreter.fromAsset('assets/models/modelb.tflite');

      final input = await _preprocessImage(image);

      var outputL = List.filled(1, List.filled(1, 0.0));
      var outputA = List.filled(1, List.filled(1, 0.0));
      var outputB = List.filled(1, List.filled(1, 0.0));

      interpreterL.run(input, outputL);
      interpreterA.run(input, outputA);
      interpreterB.run(input, outputB);

      return {
        'resultado': 'L: ${outputL[0][0].toStringAsFixed(2)} | a: ${outputA[0][0].toStringAsFixed(2)}',
        'L': outputL[0][0].toStringAsFixed(2),
        'a': outputA[0][0].toStringAsFixed(2),
        'b': outputB[0][0].toStringAsFixed(2),
      };
    } catch (e) {
      print('Error processing image: $e');
      return null;
    } finally {
      interpreterL?.close();
      interpreterA?.close();
      interpreterB?.close();
    }
  }

  /// Pré-processamento original (Listas aninhadas)
  Future<List<List<List<List<double>>>>> _preprocessImage(File image) async {
    try {
      final imageBytes = await image.readAsBytes();
      final img.Image? originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) throw Exception("Error decoding image.");

      final img.Image resizedImage = img.copyResize(originalImage, width: 224, height: 224);

      final input = List.generate(
        1,
        (batch) => List.generate(
          224,
          (y) => List.generate(
            224,
            (x) {
              final pixel = resizedImage.getPixel(x, y);
              // Compatibilidade com image v4+ (acesso direto a r, g, b)
              final r = pixel.r / 255.0;
              final g = pixel.g / 255.0;
              final b = pixel.b / 255.0;
              return [r, g, b];
            },
          ),
        ),
      );
      return input.cast<List<List<List<double>>>>();
    } catch (e) {
      print('Error preprocessing image: $e');
      rethrow;
    }
  }

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
                              Container(
                                width: 100,
                                height: 100,
                                child: Image.file(item['image'], fit: BoxFit.cover),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Resultado: ${item['resultado']}',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton(
                            icon: Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteImage(index),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            builder: (BuildContext context) {
              return Wrap(
                children: [
                  ListTile(
                    leading: Icon(Icons.camera_alt),
                    title: Text('Tirar Foto (Validada)'),
                    onTap: () {
                      Navigator.pop(context);
                      _captureWithCustomCamera();
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.image),
                    title: Text('Escolher da Galeria'),
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

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'L*a*b*',
      home: SplashScreen(),
    );
  }
}