import 'package:image/image.dart' as img;
import 'dart:math';

/// Função para detectar a região rosa (Alizarol) e realizar um recorte 
/// geométrico centralizado na amostra, garantindo que bordas pálidas sejam incluídas.
img.Image? detectPinkAndCrop(img.Image image) {
  // --- PASSO 1: PRÉ-RECORTE CENTRAL (Filtro de Ambiente) ---
  // Isolamos 75% da área central para eliminar fundos como toalhas de mesa.
  int side = (min(image.width, image.height) * 0.75).toInt();
  int centerX = (image.width - side) ~/ 2;
  int centerY = (image.height - side) ~/ 2;

  img.Image centralSquare = img.copyCrop(
    image,
    x: centerX,
    y: centerY,
    width: side,
    height: side,
  );

  // --- PASSO 2: MAPEAMENTO DA MASSA COLORIDA ---
  int minX = centralSquare.width;
  int minY = centralSquare.height;
  int maxX = 0;
  int maxY = 0;
  bool found = false;

  for (int y = 0; y < centralSquare.height; y += 5) {
    for (int x = 0; x < centralSquare.width; x += 5) {
      final pixel = centralSquare.getPixel(x, y);
      
      final hsv = rgbToHsv(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
      final h = hsv[0];
      final s = hsv[1];
      final v = hsv[2];

      // Faixa de cor: Rosa/Magenta do Alizarol
      bool hueOk = ((h >= 0 && h <= 30) || (h >= 290 && h <= 360));

      // Saturação baixa (0.12) para tentar pegar o máximo da amostra
      if (hueOk && s > 0.12 && v > 0.15) {
        found = true;
        
        // Opcional: Marcar pixels para conferência no script de teste
        // centralSquare.setPixelRgb(x, y, 0, 255, 0); 

        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }

  // Se não encontrar nada rosa, retorna o centro fixo por segurança
  if (!found) return centralSquare; 

  // --- PASSO 3: CÁLCULO DO CENTRO DE MASSA E RAIO ---
  // Encontramos o centro geométrico da mancha rosa detectada
  int pinkCenterX = (minX + maxX) ~/ 2;
  int pinkCenterY = (minY + maxY) ~/ 2;

  // Calculamos a maior distância do centro até as bordas detectadas
  int distX = max(pinkCenterX - minX, maxX - pinkCenterX);
  int distY = max(pinkCenterY - minY, maxY - pinkCenterY);
  
  // Criamos um diâmetro que é 35% maior que a mancha detectada.
  // Isso "força" o enquadramento das bordas que estão quase brancas.
  int sideLength = (max(distX, distY) * 1.35 * 2).toInt();

  // --- PASSO 4: RECORTE FINAL (SQUARE CROP) ---
  int finalCropX = (pinkCenterX - (sideLength ~/ 2)).clamp(0, centralSquare.width);
  int finalCropY = (pinkCenterY - (sideLength ~/ 2)).clamp(0, centralSquare.height);
  
  int finalCropW = sideLength.clamp(1, centralSquare.width - finalCropX);
  int finalCropH = sideLength.clamp(1, centralSquare.height - finalCropY);

  return img.copyCrop(
    centralSquare,
    x: finalCropX,
    y: finalCropY,
    width: finalCropW,
    height: finalCropH
  );
}

/// Converte RGB para HSV com correção de Matiz (Hue) negativo.
List<double> rgbToHsv(int r, int g, int b) {
  double rf = r / 255;
  double gf = g / 255;
  double bf = b / 255;
  double maxV = max(rf, max(gf, bf));
  double minV = min(rf, min(gf, bf));
  double delta = maxV - minV;
  double h = 0;
  if (delta != 0) {
    if (maxV == rf) h = (gf - bf) / delta % 6;
    else if (maxV == gf) h = (bf - rf) / delta + 2;
    else h = (rf - gf) / delta + 4;
    h *= 60;
    if (h < 0) h += 360;
  }
  return [h, maxV == 0 ? 0 : delta / maxV, maxV];
}