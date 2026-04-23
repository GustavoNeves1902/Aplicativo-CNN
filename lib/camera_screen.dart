import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'detector.dart';

/// Fração do menor lado usada pelo círculo guia.
const double _kGuideFraction = 0.78;

/// Throttle de auto-captura: processa no máximo 1 frame a cada N milissegundos.
const int _kFrameThrottleMs = 500;

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────

/// Tela de câmera com auto-captura por detecção de círculo (HoughCircles).
///
/// - A câmera analisa frames continuamente em background (via [compute]).
/// - Quando um círculo é detectado, a foto é tirada automaticamente.
/// - O botão manual de captura permanece disponível como fallback.
class CameraScreen extends StatefulWidget {
  final Function(String) onImageCaptured;
  const CameraScreen({Key? key, required this.onImageCaptured})
      : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  bool _capturing = false;       // true enquanto takePicture() está em andamento
  bool _initialized = false;
  bool _autoCapturing = false;   // true enquanto o Isolate está processando um frame
  bool _circleDetected = false;  // true após círculo confirmado

  DateTime _lastFrameCheck = DateTime.now();

  // Animação de pulso no círculo guia (scanning)
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _initCamera();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  // ── Câmera ─────────────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.medium, // ≈720p — suficiente para detecção, muito mais rápido
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420, // Android; iOS usa BGRA implicitamente
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;
      setState(() => _initialized = true);

      // Inicia stream contínuo de frames para auto-captura
      await _controller!.startImageStream(_onFrame);
    } catch (e) {
      print('[Camera] Erro ao inicializar: $e');
    }
  }

  // ── Auto-Capture: recebe frames do stream ─────────────────────────────────

  /// Callback chamado a cada frame da câmera.
  /// Aplica throttle e descarta frames enquanto um Isolate já está ativo.
  void _onFrame(CameraImage frame) {
    if (_autoCapturing || _circleDetected || _capturing) return;

    final now = DateTime.now();
    if (now.difference(_lastFrameCheck).inMilliseconds < _kFrameThrottleMs) return;
    _lastFrameCheck = now;

    _processFrameInBackground(frame);
  }

  /// Converte o frame e envia para o Isolate. Se um círculo for detectado,
  /// dispara a captura automática.
  Future<void> _processFrameInBackground(CameraImage frame) async {
    if (!mounted) return;
    setState(() => _autoCapturing = true);
    try {
      // 1. Conversão CameraImage → JPEG (main thread; operação de bytes, rápida)
      final Uint8List jpeg = cameraImageToJpeg(frame);
      if (jpeg.isEmpty) return;

      // 2. HoughCircles em Isolate secundário — não bloqueia a UI
      final Uint8List? cropped = await compute(detectCircleOnFrame, jpeg);

      if (cropped != null && !_circleDetected && mounted) {
        setState(() => _circleDetected = true);
        print('[AutoCapture] Círculo detectado — disparando captura...');

        // Pequeno delay para o usuário ver o flash verde antes da foto
        await Future.delayed(const Duration(milliseconds: 250));
        if (mounted && !_capturing) await _captureAuto();
      }
    } catch (e) {
      print('[AutoCapture] Erro: $e');
    } finally {
      if (mounted) setState(() => _autoCapturing = false);
    }
  }

  /// Captura automática: para o stream e tira foto de alta qualidade.
  Future<void> _captureAuto() async {
    if (_capturing || _controller == null || !_initialized) return;
    setState(() => _capturing = true);
    try {
      await _controller!.stopImageStream();
      final XFile file = await _controller!.takePicture();
      if (mounted) Navigator.pop(context, file.path);
    } catch (e) {
      print('[AutoCapture] Erro na captura automática: $e');
      if (mounted) setState(() { _capturing = false; _circleDetected = false; });
    }
  }

  // ── Captura Manual (botão) ─────────────────────────────────────────────────

  Future<void> _capture() async {
    if (_capturing || _controller == null || !_initialized) return;
    setState(() => _capturing = true);
    try {
      // Para o stream antes de tirar foto (exigido pelo pacote camera)
      try { await _controller!.stopImageStream(); } catch (_) {}
      final XFile file = await _controller!.takePicture();
      if (mounted) Navigator.pop(context, file.path);
    } catch (e) {
      print('[Camera] Erro ao capturar: $e');
      if (mounted) setState(() => _capturing = false);
    }
  }

  // ── Helpers de estado visual ───────────────────────────────────────────────

  Color get _guideColor {
    if (_circleDetected) return Colors.greenAccent;
    if (_capturing)      return Colors.grey.shade400;
    return Colors.white;
  }

  String get _statusLabel {
    if (_capturing)       return 'Capturando...';
    if (_circleDetected)  return '✅ Placa detectada!';
    return '🔍 Buscando placa automaticamente...';
  }

  Color get _statusBg {
    if (_circleDetected) return Colors.green.withOpacity(0.85);
    return Colors.black54;
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

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
          final double guideSize =
              [w, h].reduce((a, b) => a < b ? a : b) * _kGuideFraction;

          return Stack(
            fit: StackFit.expand,
            children: [

              // ── Preview da câmera ────────────────────────────────────────
              CameraPreview(_controller!),

              // ── Overlay escuro com "buraco" circular ─────────────────────
              CustomPaint(
                painter: _DarkMaskPainter(
                  guideRadius: guideSize / 2,
                  center: Offset(w / 2, h / 2),
                ),
              ),

              // ── Borda animada do círculo guia ─────────────────────────────
              Center(
                child: AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, __) => Transform.scale(
                    scale: (_capturing || _circleDetected) ? 1.0 : _pulseAnim.value,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width:  guideSize,
                      height: guideSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _guideColor,
                          width: _circleDetected ? 5 : 3,
                        ),
                        boxShadow: _circleDetected
                            ? [
                                BoxShadow(
                                  color: Colors.greenAccent.withOpacity(0.45),
                                  blurRadius: 24,
                                  spreadRadius: 8,
                                ),
                              ]
                            : _capturing
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

              // ── Label de status (com animação de troca) ───────────────────
              Positioned(
                bottom: h / 2 - guideSize / 2 - 48,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      key: ValueKey(_statusLabel),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: _statusBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _statusLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Badge "AUTO" — indica se o Isolate está processando ───────
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                right: 12,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _autoCapturing
                        ? Colors.amber.withOpacity(0.9)
                        : Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _autoCapturing ? Colors.amber : Colors.white30,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _autoCapturing
                            ? Icons.autorenew
                            : Icons.auto_awesome,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'AUTO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Botão de voltar ───────────────────────────────────────────
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

              // ── Botão de captura manual ───────────────────────────────────
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _capturing ? null : _capture,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 80,
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

    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
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
