library sphere;

import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart' show rootBundle;

class Sphere extends StatefulWidget {
  Sphere({Key key, this.surface, this.radius, this.latitude, this.longitude}) : super(key: key);
  final String surface;
  final double radius;
  final double latitude;
  final double longitude;

  @override
  _SphereState createState() => _SphereState();
}

class _SphereState extends State<Sphere> with TickerProviderStateMixin {
  Uint32List surface;
  double surfaceWidth;
  double surfaceHeight;
  double zoom = 0;
  double rotationX = 0;
  double rotationZ = 0;
  double _lastZoom;
  double _lastRotationX;
  double _lastRotationZ;
  Offset _lastFocalPoint;
  AnimationController rotationZController;
  Animation<double> rotationZAnimation;
  double get radius => widget.radius * math.pow(2, zoom);

  Future<ui.Image> buildSphere() {
    if (surface == null) return null;
    final r = radius.roundToDouble();
    final minX = -r;
    final minY = -r;
    final maxX = r;
    final maxY = r;
    final width = maxX - minX;
    final height = maxY - minY;
    final sphere = Uint32List(width.toInt() * height.toInt());

    var angle = math.pi / 2 - rotationX;
    final sinx = math.sin(angle);
    final cosx = math.cos(angle);
    // angle = 0;
    // final siny = math.sin(angle);
    // final cosy = math.cos(angle);
    angle = rotationZ + math.pi / 2;
    final sinz = math.sin(angle);
    final cosz = math.cos(angle);

    final surfaceXRate = (surfaceWidth - 1) / (2.0 * math.pi);
    final surfaceYRate = (surfaceHeight - 1) / (math.pi);

    for (var y = minY; y < maxY; y++) {
      final sphereY = (-y - minY - 1) * width;
      for (var x = minX; x < maxX; x++) {
        var z = r * r - x * x - y * y;
        if (z > 0) {
          z = math.sqrt(z);

          var x1 = x, y1 = y, z1 = z;
          double x2, y2, z2;
          //rotate around the X axis
          y2 = y1 * cosx - z1 * sinx;
          z2 = y1 * sinx + z1 * cosx;
          y1 = y2;
          z1 = z2;
          //rotate around the Y axis
          // x2 = x1 * cosy + z1 * siny;
          // z2 = -x1 * siny + z1 * cosy;
          // x1 = x2;
          // z1 = z2;
          //rotate around the Z axis
          x2 = x1 * cosz - y1 * sinz;
          y2 = x1 * sinz + y1 * cosz;
          x1 = x2;
          y1 = y2;

          final lat = math.asin(z1 / r);
          final lon = math.atan2(y1, x1);

          final x0 = (lon + math.pi) * surfaceXRate;
          final y0 = (math.pi / 2 - lat) * surfaceYRate;

          final color = surface[(y0.toInt() * surfaceWidth + x0).toInt()];
          sphere[(sphereY + x - minX).toInt()] = color;
        }
      }
    }

    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      sphere.buffer.asUint8List(),
      width.toInt(),
      height.toInt(),
      ui.PixelFormat.rgba8888,
      (image) => c.complete(image),
    );
    return c.future;
  }

  void loadSurface() {
    rootBundle.load(widget.surface).then((data) {
      ui.decodeImageFromList(data.buffer.asUint8List(), (image) {
        image.toByteData(format: ui.ImageByteFormat.rawRgba).then((pixels) {
          surface = pixels.buffer.asUint32List();
          surfaceWidth = image.width.toDouble();
          surfaceHeight = image.height.toDouble();
          setState(() {});
        });
      });
    });
  }

  @override
  void initState() {
    super.initState();
    rotationX = widget.latitude * math.pi / 180;
    rotationZ = widget.longitude * math.pi / 180;
    rotationZController = AnimationController(vsync: this)
      ..addListener(() {
        setState(() => rotationZ = rotationZAnimation.value);
      });
    loadSurface();
  }

  @override
  void dispose() {
    rotationZController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: (ScaleStartDetails details) {
        _lastZoom = zoom;
        _lastRotationX = rotationX;
        _lastRotationZ = rotationZ;
        _lastFocalPoint = details.focalPoint;
        rotationZController.stop();
      },
      onScaleUpdate: (ScaleUpdateDetails details) {
        zoom = _lastZoom + math.log(details.scale) / math.ln2;
        final offset = details.focalPoint - _lastFocalPoint;
        rotationX = _lastRotationX + offset.dy / radius;
        rotationZ = _lastRotationZ - offset.dx / radius;
        setState(() {});
      },
      onScaleEnd: (ScaleEndDetails details) {
        final a = -300;
        final v = details.velocity.pixelsPerSecond.dx * 0.3;
        final t = (v / a).abs() * 1000;
        final s = (v.sign * 0.5 * v * v / a) / radius;
        rotationZController.duration = Duration(milliseconds: t.toInt());
        rotationZAnimation = Tween<double>(begin: rotationZ, end: rotationZ + s).animate(CurveTween(curve: Curves.decelerate).animate(rotationZController));
        rotationZController
          ..value = 0
          ..forward();
      },
      child: FutureBuilder(
        future: buildSphere(),
        builder: (BuildContext context, AsyncSnapshot<ui.Image> snapshot) {
          return CustomPaint(
            painter: SpherePainter(image: snapshot.data, radius: radius),
            size: Size(radius * 2, radius * 2),
          );
        },
      ),
    );
  }
}

class SpherePainter extends CustomPainter {
  SpherePainter({this.image, this.radius});
  final ui.Image image;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (image == null) return;
    final paint = Paint();
    final offset = Offset(size.width / 2, size.height / 2);
    var rect = Rect.fromCircle(center: offset, radius: radius - 1);
    final path = Path()..addOval(rect);
    canvas.clipPath(path);
    rect = Rect.fromCircle(center: offset, radius: radius);
    canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), rect, paint);

    final gradient = RadialGradient(
      center: Alignment.center,
      colors: [Colors.transparent, Colors.black.withOpacity(0.35), Colors.black.withOpacity(0.5)],
      stops: [0.1, 0.85, 1.0],
    );
    paint.shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}
