import 'dart:io';
import 'dart:convert';
import 'package:Alizarol_app/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Alizarol_app/camera_screen.dart';
import 'detector.dart';
import 'dart:math';
import 'dart:typed_data';

class ImagePredictorApp extends StatefulWidget {
  @override
  _ImagePredictorAppState createState() => _ImagePredictorAppState();
}

class _ImagePredictorAppState extends State<ImagePredictorApp> {
  final List<Map<String, dynamic>> _processedImages = [];
  final ImagePicker _picker = ImagePicker();
  late Interpreter _interpreter;

  @override
  void initState() {
    super.initState();
    _loadModel();
    _loadProcessedImages();
  }

  Future<void> _loadModel() async {
    _interpreter = await Interpreter.fromAsset('assets/models/model.tflite');
    print("Modelo carregado com sucesso");
  }

  /// FUNÇÃO MESTRE: Processa a imagem capturada pela câmera.
  /// O dashboard exibe a imagem RECORTADA (o que o modelo viu).
  Future<void> _handleProcessedImage(File image) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempDir = Directory.systemTemp;

    // 1. Decodifica a imagem original
    final bytes = await image.readAsBytes();
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return;

    // 2. DETECTA A BORDA CIRCULAR DA PLACA via OpenCV (HoughCircles) + padding 70px
    img.Image finalImage = detectPetriAndCrop(decoded);

    // 3. SALVA A IMAGEM RECORTADA para exibição no dashboard (≤800px, boa qualidade)
    img.Image displayImage = finalImage.width > 800
        ? img.copyResize(finalImage, width: 800)
        : finalImage;
    final displayFile = File('${tempDir.path}/display_$timestamp.jpg');
    await displayFile.writeAsBytes(img.encodeJpg(displayImage, quality: 90));

    // 4. REDIMENSIONAMENTO PARA A IA (224×224) — usado APENAS para inferência
    img.Image resized = img.copyResize(finalImage, width: 224, height: 224);
    final inferenceFile = File('${tempDir.path}/inference_$timestamp.jpg');
    await inferenceFile.writeAsBytes(img.encodeJpg(resized));

    // 5. INFERÊNCIA com a imagem recortada
    final predictions = await _processImage(inferenceFile);

    if (predictions != null) {
      setState(() {
        _processedImages.add({
          'image': displayFile, // dashboard mostra a imagem recortada
          'resultado': predictions['resultado'],
          'timestamp': DateTime.now().toIso8601String(),
        });
      });
      _saveProcessedImages();
    }
  }

  /// Inferência TFLite com Softmax
  Future<Map<String, String>?> _processImage(File image) async {
    try {
      final input = await _preprocessImageForClassification(image);
      var output = List.filled(1, List.filled(2, 0.0));

      _interpreter.run(input, output);

      List<double> rawResults = List<double>.from(output[0]);
      List<double> probabilities = _softmax(rawResults);

      double probAprovado = probabilities[0];
      double probReprovado = probabilities[1];

      String resultadoFinal =
          probAprovado > probReprovado ? "APROVADO" : "REPROVADO";
      String confianca =
          (max(probAprovado, probReprovado) * 100).toStringAsFixed(1);

      return {
        'resultado': '$resultadoFinal ($confianca%)',
      };
    } catch (e) {
      print('Erro na classificação: $e');
      return null;
    }
  }

  /// Pré-processamento NHWC (Padrão do seu modelo TFLite)
  Future<List<List<List<List<double>>>>> _preprocessImageForClassification(
      File image) async {
    final imageBytes = await image.readAsBytes();
    final img.Image? originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) throw Exception("Erro ao decodificar");

    final img.Image resizedImage =
        img.copyResize(originalImage, width: 224, height: 224);

    var input = List.generate(
        1,
        (_) => List.generate(224,
            (_) => List.generate(224, (_) => List.generate(3, (_) => 0.0))));

    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final pixel = resizedImage.getPixel(x, y);
        input[0][y][x][0] = pixel.r / 255.0;
        input[0][y][x][1] = pixel.g / 255.0;
        input[0][y][x][2] = pixel.b / 255.0;
      }
    }
    return input;
  }

  // --- MÉTODOS DE UI E PERSISTÊNCIA (MANTIDOS) ---

  List<double> _softmax(List<double> logits) {
    double maxLogit = logits.reduce(max);
    List<double> exps = logits.map((l) => exp(l - maxLogit)).toList();
    double sumExps = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sumExps).toList();
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) await _handleProcessedImage(File(pickedFile.path));
  }

  Future<void> _captureWithCustomCamera() async {
    final String? imagePath = await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) =>
                CameraScreen(onImageCaptured: (path) => path)));
    if (imagePath != null) await _handleProcessedImage(File(imagePath));
  }

  Future<void> _saveProcessedImages() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _processedImages
        .map((item) => {
              'path': item['image'].path,
              'resultado': item['resultado'],
              'timestamp': item['timestamp']
            })
        .toList();
    await prefs.setString('processed_images', jsonEncode(data));
  }

  Future<void> _loadProcessedImages() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('processed_images');
    if (data != null) {
      setState(() {
        _processedImages.clear();
        _processedImages.addAll(
            List<Map<String, dynamic>>.from(jsonDecode(data)).map((item) => {
                  'image': File(item['path']),
                  'resultado': item['resultado'],
                  'timestamp': item['timestamp']
                }));
      });
    }
  }

  void _deleteImage(int index) {
    setState(() => _processedImages.removeAt(index));
    _saveProcessedImages();
  }

  void _showFullImage(BuildContext context, File imageFile, String resultado) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(10),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(imageFile, fit: BoxFit.contain))),
            Positioned(
                top: 10,
                right: 10,
                child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                        icon: Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context)))),
            Positioned(
                bottom: 20,
                child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(resultado,
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)))),
          ],
        ),
      ),
    );
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
            ? Center(child: Text('Nenhuma imagem selecionada'))
            : ListView.builder(
                itemCount: _processedImages.length,
                itemBuilder: (context, index) {
                  final item = _processedImages[index];
                  final String resultado = item['resultado'];
                  final bool reprovado = resultado.contains('REPROVADO');
                  final Color resultColor = reprovado ? Colors.red : Colors.green;

                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      onTap: () => _showFullImage(
                          context, item['image'], resultado),
                      leading: Image.file(item['image'],
                          width: 60, height: 60, fit: BoxFit.cover),
                      title: Text(resultado,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: resultColor)),
                      subtitle: Text(item['timestamp'].split('T')[0]),
                      trailing: IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteImage(index)),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
              context: context,
              builder: (ctx) => Wrap(children: [
                    ListTile(
                        leading: Icon(Icons.camera_alt),
                        title: Text('Tirar Foto'),
                        onTap: () {
                          Navigator.pop(ctx);
                          _captureWithCustomCamera();
                        }),
                    ListTile(
                        leading: Icon(Icons.image),
                        title: Text('Galeria'),
                        onTap: () {
                          Navigator.pop(ctx);
                          _pickImage(ImageSource.gallery);
                        }),
                  ]));
        },
        backgroundColor: Colors.blue,
        child: Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  @override
  void dispose() {
    _interpreter.close();
    super.dispose();
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
