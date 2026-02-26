import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class CameraScreen extends StatefulWidget {
  final Function(String) onImageCaptured;

  const CameraScreen({Key? key, required this.onImageCaptured})
      : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isValid = false;
  bool _isProcessing = false;
  Color _overlayColor = Colors.red.withOpacity(0.3);

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final camera = cameras.first;

    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _controller!.initialize();

    _controller!.startImageStream((CameraImage image) {
      if (!_isProcessing) {
        _isProcessing = true;
        _analyzeFrame(image);
      }
    });

    setState(() {});
  }

  void _analyzeFrame(CameraImage image) {
    try {
      final plane = image.planes[0];
      Uint8List bytes = plane.bytes;

      int total = 0;
      for (int i = 0; i < bytes.length; i += 10) {
        total += bytes[i];
      }

      double avgBrightness = total / (bytes.length / 10);

      bool brightnessValid = avgBrightness > 60 && avgBrightness < 180;

      bool distanceValid = avgBrightness > 80 && avgBrightness < 160;

      bool valid = brightnessValid && distanceValid;

      setState(() {
        _isValid = valid;
        _overlayColor =
            valid ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3);
      });
    } catch (_) {}

    _isProcessing = false;
  }

  Future<void> _capture() async {
    if (!_isValid) return;

    final file = await _controller!.takePicture();
    // Fecha a tela e retorna o path para quem chamou
    Navigator.pop(context, file.path);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // 1. Preview da Câmera preenchendo a tela
          Positioned.fill(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: CameraPreview(_controller!),
            ),
          ),

          // 2. Visor Visual (Guia para o frasco)
          Positioned.fill(
            child: CustomPaint(
              painter: CameraGuidePainter(color: _overlayColor),
            ),
          ),

          // 3. UI de Instruções e Botão
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _isValid
                        ? "Posição correta"
                        : "Centralize o frasco e ajuste a luz",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FloatingActionButton(
                  backgroundColor: _isValid ? Colors.green : Colors.grey,
                  onPressed: _capture,
                  child: const Icon(Icons.camera, size: 30),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class CameraGuidePainter extends CustomPainter {
  final Color color;

  CameraGuidePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.35;

    // 1. Criar o fundo semi-transparente
    final backgroundPaint = Paint()..color = Colors.black.withOpacity(0.5);

    // 2. Criar o caminho para a máscara (tela inteira menos o círculo)
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(backgroundPath, backgroundPaint);

    // 3. Desenhar a borda do círculo (o que você já tinha)
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    canvas.drawCircle(center, radius, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
