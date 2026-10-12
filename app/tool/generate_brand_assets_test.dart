// Gera os ícones do app (iOS/Android) e a imagem da tela de abertura a partir do
// símbolo vetorial em lib/widgets/logo.dart.
//
// Uso (na pasta app/):  flutter test tool/generate_brand_assets_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:entreggo/theme.dart';
import 'package:entreggo/widgets/logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _iconBackground = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF0F2D57), EntreggoColors.navy],
);

typedef _Draw = void Function(Canvas canvas, Size size);

/// Ícone quadrado: fundo azul-marinho e símbolo centralizado.
void _drawIcon(Canvas canvas, Size size, {double cornerRadius = 0}) {
  final rect = Offset.zero & size;
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius)),
    Paint()..shader = _iconBackground.createShader(rect),
  );
  _drawMark(canvas, size, widthFactor: 0.68);
}

void _drawMark(Canvas canvas, Size size, {required double widthFactor}) {
  final w = size.width * widthFactor;
  final h = w / EntreggoMarkPainter.aspectRatio;
  canvas.save();
  canvas.translate((size.width - w) / 2, (size.height - h) / 2);
  const EntreggoMarkPainter().paint(canvas, Size(w, h));
  canvas.restore();
}

Future<void> _render(
  WidgetTester tester,
  String path,
  int width,
  int height,
  _Draw draw, {
  bool opaque = false,
}) async {
  final bytes = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    draw(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  });
  final file = File(path)..createSync(recursive: true);
  file.writeAsBytesSync(_encodePng(width, height, bytes!, opaque: opaque));
}

/// Codificador PNG mínimo. `opaque` grava RGB sem canal alfa (exigência da App Store).
Uint8List _encodePng(int w, int h, Uint8List rgba, {required bool opaque}) {
  final channels = opaque ? 3 : 4;
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0);
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final a = rgba[i + 3];
      if (opaque) {
        // rawRgba vem pré-multiplicado; sobre fundo opaco a == 255.
        raw.add([rgba[i], rgba[i + 1], rgba[i + 2]]);
      } else if (a == 0) {
        raw.add(const [0, 0, 0, 0]);
      } else {
        int un(int c) => (c * 255 / a).round().clamp(0, 255);
        raw.add([un(rgba[i]), un(rgba[i + 1]), un(rgba[i + 2]), a]);
      }
    }
  }
  final header = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8)
    ..setUint8(9, channels == 3 ? 2 : 6);
  return (BytesBuilder()
        ..add(const [137, 80, 78, 71, 13, 10, 26, 10])
        ..add(_chunk('IHDR', header.buffer.asUint8List()))
        ..add(_chunk('IDAT', ZLibCodec(level: 9).encode(raw.takeBytes())))
        ..add(_chunk('IEND', Uint8List(0))))
      .takeBytes();
}

Uint8List _chunk(String type, List<int> data) {
  final typed = [...ascii.encode(type), ...data];
  final out = ByteData(12 + data.length)..setUint32(0, data.length);
  final bytes = out.buffer.asUint8List()..setRange(4, 8 + data.length, typed);
  out.setUint32(8 + data.length, _crc32(typed));
  return bytes;
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

void main() {
  testWidgets('gera ícones e tela de abertura', (tester) async {
    // iOS: todos os tamanhos listados no AppIcon.appiconset.
    const iosDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final contents =
        jsonDecode(File('$iosDir/Contents.json').readAsStringSync()) as Map;
    for (final img in (contents['images'] as List).cast<Map>()) {
      final pt = double.parse((img['size'] as String).split('x').first);
      final scale = int.parse((img['scale'] as String).replaceAll('x', ''));
      final px = (pt * scale).round();
      await _render(
        tester,
        '$iosDir/${img['filename']}',
        px,
        px,
        _drawIcon,
        opaque: true,
      );
    }

    // Android: ícone legado arredondado + ícone adaptativo (API 26+).
    const densities = {
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    };
    for (final MapEntry(key: name, value: d) in densities.entries) {
      final dir = 'android/app/src/main/res/mipmap-$name';
      final legacy = (48 * d).round();
      await _render(
        tester,
        '$dir/ic_launcher.png',
        legacy,
        legacy,
        (c, s) => _drawIcon(c, s, cornerRadius: s.width * 0.2),
      );
      final adaptive = (108 * d).round();
      await _render(
        tester,
        '$dir/ic_launcher_foreground.png',
        adaptive,
        adaptive,
        (c, s) => _drawMark(c, s, widthFactor: 0.5),
      );
    }

    // Tela de abertura do iOS (LaunchImage centralizada no storyboard).
    const launchDir = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
    for (final (suffix, scale) in [('', 1), ('@2x', 2), ('@3x', 3)]) {
      await _render(
        tester,
        '$launchDir/LaunchImage$suffix.png',
        140 * scale,
        (140 / EntreggoMarkPainter.aspectRatio).round() * scale,
        (c, s) => _drawMark(c, s, widthFactor: 1),
      );
    }

    // Prévia para revisão (não versionada).
    await _render(
      tester,
      'build/brand_preview/icon_1024.png',
      1024,
      1024,
      (c, s) => _drawIcon(c, s, cornerRadius: s.width * 0.225),
    );
  });
}
