import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:io';

class CameraScreen extends StatefulWidget {
  final Function(String) onImageCaptured;
  const CameraScreen({Key? key, required this.onImageCaptured})
      : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isProcessing = false;
  double _brightness = 0;
  String _message = "Aguarde...";
  bool _isLightOk = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.high, // Resolução alta para melhor classificação depois
      enableAudio: false,
    );

    await _controller!.initialize();

    // Inicia fluxo de frames para analisar brilho sem tirar foto
    _controller!.startImageStream((CameraImage image) {
      if (_isProcessing) return;
      _isProcessing = true;
      _analyzeLight(image);
    });

    if (mounted) setState(() {});
  }

  /// Analisa o plano Y (luminância) da imagem para avisar se o ambiente está escuro
  void _analyzeLight(CameraImage image) {
    // Pegamos a média de brilho do plano Y (luminância)
    final bytes = image.planes[0].bytes;
    int total = 0;
    // Amostragem de 1 em cada 100 pixels para não pesar
    for (int i = 0; i < bytes.length; i += 100) {
      total += bytes[i];
    }

    double avg = total / (bytes.length / 100);

    if (mounted) {
      setState(() {
        _brightness = avg;
        if (avg < 40) {
          _message = "Ambiente muito escuro 🌑";
          _isLightOk = false;
        } else if (avg > 220) {
          _message = "Muita luz! Evite reflexos ☀️";
          _isLightOk = false;
        } else {
          _message = "Posicione o frasco no centro";
          _isLightOk = true;
        }
      });
    }
    _isProcessing = false;
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      final XFile file = await _controller!.takePicture();
      // Retorna o path original. O recorte você pode fazer na main ou após a captura
      Navigator.pop(context, file.path);
    } catch (e) {
      print("Erro ao capturar: $e");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

// No arquivo camera_screen.dart

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Definimos o tamanho do visor como 70% da largura da tela
    double viewSize = MediaQuery.of(context).size.width * 0.7;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          CameraPreview(_controller!),

          // --- MÁSCARA VISUAL (O "Círculo" no visor) ---
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.5),
              BlendMode.srcOut,
            ),
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Center(
                  child: Container(
                    width: viewSize,
                    height: viewSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(viewSize / 2),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Instruções e Botão
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  _isLightOk
                      ? "Centralize o líquido rosa"
                      : "Iluminação insuficiente",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                FloatingActionButton(
                  backgroundColor: _isLightOk ? Colors.green : Colors.grey,
                  onPressed: _isLightOk ? _capture : null,
                  child: const Icon(Icons.camera_alt),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
