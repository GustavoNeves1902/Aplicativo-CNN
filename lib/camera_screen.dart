import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
/// Fração do menor lado usada pelo círculo guia.
const double _kGuideFraction = 0.78;

/// Tela de câmera com círculo guia estático.
/// O usuário posiciona a placa de Petri dentro do círculo e captura manualmente.
class CameraScreen extends StatefulWidget {
  final Function(String) onImageCaptured;
  const CameraScreen({Key? key, required this.onImageCaptured})
      : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  bool _capturing  = false;
  bool _initialized = false;

  // Animação de pulso no círculo guia
  late AnimationController _pulseController;
  late Animation<double>   _pulseAnim;

  @override
  void initState() {
    super.initState();
    _initCamera();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.98, end: 1.02).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  // ── Câmera ────────────────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _controller!.initialize();
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      print('[Camera] Erro ao inicializar: $e');
    }
  }

  Future<void> _capture() async {
    if (_capturing || _controller == null || !_initialized) return;
    setState(() => _capturing = true);
    try {
      final XFile file = await _controller!.takePicture();
      if (mounted) Navigator.pop(context, file.path);
    } catch (e) {
      print('[Camera] Erro ao capturar: $e');
      if (mounted) setState(() => _capturing = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_initialized || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double w = constraints.maxWidth;
          final double h = constraints.maxHeight;
          // Diâmetro do círculo guia = _kGuideFraction do menor lado da tela
          final double guideSize = [w, h].reduce((a, b) => a < b ? a : b)
              * _kGuideFraction;

          return Stack(
            fit: StackFit.expand,
            children: [
              // ── Preview da câmera ────────────────────────────────────────
              CameraPreview(_controller!),

              // ── Overlay escuro com "buraco" no círculo guia ──────────────
              CustomPaint(
                painter: _DarkMaskPainter(
                  guideRadius: guideSize / 2,
                  center: Offset(w / 2, h / 2),
                ),
              ),

              // ── Borda animada do círculo guia ────────────────────────────
              Center(
                child: AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, __) => Transform.scale(
                    scale: _capturing ? 1.0 : _pulseAnim.value,
                    child: Container(
                      width:  guideSize,
                      height: guideSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _capturing
                              ? Colors.grey.shade400
                              : Colors.white,
                          width: 3,
                        ),
                        boxShadow: _capturing
                            ? []
                            : [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.25),
                                  blurRadius: 16,
                                  spreadRadius: 4,
                                ),
                              ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Label instrução ──────────────────────────────────────────
              Positioned(
                bottom: h / 2 - guideSize / 2 - 48,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Posicione a placa de Petri dentro do círculo',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ),

              // ── Botão de voltar ──────────────────────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                left: 12,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),

              // ── Botão de captura ─────────────────────────────────────────
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _capturing ? null : _capture,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width:  80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _capturing
                            ? Colors.grey.shade700
                            : Colors.white,
                        border: Border.all(color: Colors.white70, width: 4),
                        boxShadow: _capturing
                            ? []
                            : [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.4),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                      ),
                      child: _capturing
                          ? const Padding(
                              padding: EdgeInsets.all(18),
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 3),
                            )
                          : const Icon(Icons.camera_alt,
                              color: Colors.black87, size: 36),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomPainter — máscara escura com buraco circular
// ─────────────────────────────────────────────────────────────────────────────
class _DarkMaskPainter extends CustomPainter {
  final double guideRadius;
  final Offset center;

  const _DarkMaskPainter({required this.guideRadius, required this.center});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.55);

    // Desenha o retângulo escuro cobrindo tudo
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Path com "buraco" circular
    final path = Path()
      ..addRect(fullRect)
      ..addOval(Rect.fromCircle(center: center, radius: guideRadius))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DarkMaskPainter old) =>
      old.guideRadius != guideRadius || old.center != center;
}
