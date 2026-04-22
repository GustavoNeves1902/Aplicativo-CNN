import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'dart:math';

// ─────────────────────────────────────────────────────────────────────────────
// CROP COM OPENCV — MÓDULO PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────

/// Detecta a placa de Petri com HoughCircles e recorta com padding de 70px.
/// Pipeline idêntico ao script Python fornecido.
/// Se não encontrar círculo, retorna a imagem original.
img.Image detectPetriAndCrop(img.Image image) {
  cv.Mat? mat;
  try {
    mat = _imgToMat(image);
    final result = _houghPipeline(mat);
    if (result != null) {
      final out = _matToImg(result);
      result.dispose();
      return out;
    }
  } catch (e) {
    print('[Detector] Erro HoughCircles: $e');
  } finally {
    mat?.dispose();
  }
  print('[Detector] Círculo não encontrado — usando imagem original.');
  return image;
}

// ─────────────────────────────────────────────────────────────────────────────
// PIPELINE HOUGHCIRCLES (interno)
// ─────────────────────────────────────────────────────────────────────────────

cv.Mat? _houghPipeline(cv.Mat mat) {
  // 1. Tons de Cinza
  final gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);

  // 2. Median Blur pesado (kernel 11).
  // O filtro mediano é incrivelmente eficaz para matar pequenas texturas
  // (como veios da folha, amassados de papel ou ruídos no fundo)
  // enquanto preserva bordas geométricas fortes (como a borda da placa).
  final blurred = cv.medianBlur(gray, 11);
  gray.dispose();

  // 3. Parâmetros dinâmicos do HoughCircles baseados no tamanho da imagem
  final minDim = min(mat.rows, mat.cols);
  final minDist = max(100.0, minDim * 0.15); // Permite círculos um pouco mais juntos/descentralizados
  
  // ERRO ANTERIOR: maxR estava travado em no máximo 800px.
  // Em fotos de galeria (12 Megapixels), o raio do prato pode ser muito maior
  // que 800px. Removemos a limitação "min(800, ...)" para liberar o raio gigante.
  final minR = max(20, (minDim * 0.10).toInt()); // Pelo menos 10% da imagem
  final maxR = (minDim * 0.80).toInt();          // Pode ocupar até 80% da imagem

  // Ajuste sutil do acumulador
  final double param2 = minDim > 1500 ? 50.0 : 40.0;

  final circles = cv.HoughCircles(
    blurred,
    cv.HOUGH_GRADIENT,
    1.2, // dp (resolução do acumulador pouco menor q a imagem para limpar ruídos)
    minDist,
    param1: 100,     // Limiar alto do edge detector (bordas fortes)
    param2: param2,  // Exigência de ser "muito perfeitamente circular"
    minRadius: minR,
    maxRadius: maxR,
  );
  blurred.dispose();

  if (circles.isEmpty || circles.cols == 0) {
    circles.dispose();
    return null;
  }

  // 4. Extrai o círculo com mais "votos"
  final c = circles.at<cv.Vec3f>(0, 0);
  circles.dispose();

  final x = c.val1;
  final y = c.val2;
  final r = c.val3;

  print('[Detector] Círculo: (${x.toInt()}, ${y.toInt()}), r=${r.toInt()}');

  final bx = (x - r).toInt();
  final by = (y - r).toInt();
  final bw = (2 * r).toInt();
  final bh = (2 * r).toInt();

  final xMin = max(0, bx - 70);
  final yMin = max(0, by - 70);
  final xMax = min(mat.cols, bx + bw + 70);
  final yMax = min(mat.rows, by + bh + 70);

  if (xMax <= xMin || yMax <= yMin) return null;

  return mat.region(cv.Rect(xMin, yMin, xMax - xMin, yMax - yMin)).clone();
}

// ─────────────────────────────────────────────────────────────────────────────
// CONVERSÃO img.Image ↔ OpenCV Mat
// ─────────────────────────────────────────────────────────────────────────────

cv.Mat _imgToMat(img.Image image) {
  final bytes = img.encodeJpg(image, quality: 95);
  return cv.imdecode(Uint8List.fromList(bytes), cv.IMREAD_COLOR);
}

img.Image _matToImg(cv.Mat mat) {
  final (success, bytes) = cv.imencode('.jpg', mat);
  if (!success || bytes.isEmpty) throw Exception('imencode falhou');
  return img.decodeImage(bytes) ?? (throw Exception('decodeImage falhou'));
}