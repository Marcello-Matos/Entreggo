import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Símbolo da marca Entreggo ("E" com seta e linhas de velocidade), desenhado em vetor.
class EntreggoMarkPainter extends CustomPainter {
  const EntreggoMarkPainter();

  static const _w = 930.0;
  static const _h = 720.0;
  static const aspectRatio = _w / _h;

  static const gradient = LinearGradient(
    colors: [Color(0xFF0A5CFF), EntreggoColors.primary, EntreggoColors.accent],
    stops: [0, 0.45, 1],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width / _w, size.height / _h);
    canvas
      ..save()
      ..translate((size.width - _w * s) / 2, (size.height - _h * s) / 2)
      ..scale(s);
    final paint = Paint()
      ..isAntiAlias = true
      ..shader = gradient.createShader(const Rect.fromLTWH(30, 0, 880, _h));
    for (final path in _paths) {
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  static final List<Path> _paths = [
    // Barra superior do "E".
    Path()
      ..moveTo(335, 222)
      ..cubicTo(400, 110, 470, 35, 590, 35)
      ..lineTo(880, 35)
      ..quadraticBezierTo(905, 35, 893, 57)
      ..lineTo(840, 150)
      ..quadraticBezierTo(828, 170, 800, 170)
      ..lineTo(590, 170)
      ..cubicTo(550, 170, 520, 190, 495, 222)
      ..close(),
    // Linhas de velocidade.
    _speedLine(
      top: 280,
      bottom: 345,
      left: 130,
      rightTop: 432,
      rightBottom: 397,
    ),
    _speedLine(
      top: 388,
      bottom: 455,
      left: 38,
      rightTop: 372,
      rightBottom: 335,
    ),
    _speedLine(
      top: 495,
      bottom: 560,
      left: 160,
      rightTop: 400,
      rightBottom: 365,
    ),
    // Curva inferior do "E" terminando em seta.
    Path()
      ..moveTo(560, 285)
      ..lineTo(718, 285)
      ..lineTo(718, 248)
      ..quadraticBezierTo(718, 225, 738, 238)
      ..lineTo(885, 333)
      ..quadraticBezierTo(902, 345, 885, 357)
      ..lineTo(738, 470)
      ..quadraticBezierTo(712, 488, 712, 460)
      ..lineTo(712, 422)
      ..lineTo(518, 422)
      ..cubicTo(440, 422, 440, 548, 518, 548)
      ..lineTo(800, 548)
      ..quadraticBezierTo(835, 548, 820, 578)
      ..lineTo(775, 668)
      ..quadraticBezierTo(763, 690, 735, 690)
      ..lineTo(480, 690)
      ..cubicTo(360, 690, 292, 615, 300, 520)
      ..quadraticBezierTo(302, 495, 330, 495)
      ..lineTo(375, 495)
      ..lineTo(462, 335)
      ..cubicTo(480, 302, 515, 285, 560, 285)
      ..close(),
  ];

  static Path _speedLine({
    required double top,
    required double bottom,
    required double left,
    required double rightTop,
    required double rightBottom,
  }) {
    final r = (bottom - top) / 2;
    return Path()
      ..moveTo(left + r, top)
      ..lineTo(rightTop, top)
      ..lineTo(rightBottom, bottom)
      ..lineTo(left + r, bottom)
      ..arcToPoint(Offset(left + r, top), radius: Radius.circular(r))
      ..close();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class EntreggoMark extends StatelessWidget {
  const EntreggoMark({super.key, this.width = 96});

  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width / EntreggoMarkPainter.aspectRatio,
    child: const CustomPaint(painter: EntreggoMarkPainter()),
  );
}

/// Logo completo: símbolo, nome e slogan.
class EntreggoLogo extends StatelessWidget {
  const EntreggoLogo({super.key, this.markWidth = 112});

  final double markWidth;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Entreggo. Sua rota. Otimizada.',
    child: ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EntreggoMark(width: markWidth),
          SizedBox(height: markWidth * 0.18),
          Text(
            'Entreggo',
            style: TextStyle(
              fontSize: markWidth * 0.38,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: EntreggoColors.navy,
              height: 1,
            ),
          ),
          SizedBox(height: markWidth * 0.08),
          Text(
            'Sua rota. Otimizada.',
            style: TextStyle(
              fontSize: markWidth * 0.135,
              letterSpacing: 2.2,
              color: EntreggoColors.slate,
            ),
          ),
        ],
      ),
    ),
  );
}
