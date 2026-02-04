import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrImageWidget extends StatelessWidget {
  final QrImage qrImage; // your custom class
  final double size;
  final Color darkColor;
  final Color lightColor;

  const QrImageWidget({
    required this.qrImage,
    this.size = 140,
    this.darkColor = Colors.black,
    this.lightColor = Colors.white,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final moduleCount = qrImage.moduleCount;
    final moduleSize = size / moduleCount;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _QrPainter(
          qrImage: qrImage,
          moduleSize: moduleSize,
          darkColor: darkColor,
          lightColor: lightColor,
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  final QrImage qrImage;
  final double moduleSize;
  final Color darkColor;
  final Color lightColor;

  _QrPainter({
    required this.qrImage,
    required this.moduleSize,
    required this.darkColor,
    required this.lightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (int r = 0; r < qrImage.moduleCount; r++) {
      for (int c = 0; c < qrImage.moduleCount; c++) {
        paint.color = qrImage.isDark(r, c) ? darkColor : lightColor;
        canvas.drawRect(
          Rect.fromLTWH(c * moduleSize, r * moduleSize, moduleSize, moduleSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
