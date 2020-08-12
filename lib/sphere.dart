library sphere;

import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart' show rootBundle;

class Sphere extends StatefulWidget {
  Sphere(
      {Key key,
      this.surface,
      this.radius,
      this.latitude = 0,
      this.longitude = 0,
      this.frontFaceColor = Colors.white,
      this.backFaceColor = Colors.white60,
      this.alignment = Alignment.center,
      this.allowsZoom = false})
      : super(key: key);
  final String surface;
  final double radius;
  final double latitude;
  final double longitude;
  final Alignment alignment;
  final bool allowsZoom;

  final Color frontFaceColor;
  final Color backFaceColor;

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

  Future<SphereImages> buildSphere(double maxWidth, double maxHeight) {
    if (surface == null) return null;
    final r = radius.roundToDouble();
    final minX = math.max(-r, (-1 - widget.alignment.x) * maxWidth / 2);
    final minY = math.max(-r, (-1 + widget.alignment.y) * maxHeight / 2);
    final maxX = math.min(r, (1 - widget.alignment.x) * maxWidth / 2);
    final maxY = math.min(r, (1 + widget.alignment.y) * maxHeight / 2);
    final width = maxX - minX;
    final height = maxY - minY;
    if (width <= 0 || height <= 0) return null;
    final frontSpherePixels = Uint32List(width.toInt() * height.toInt());
    final backSpherePixels = Uint32List(width.toInt() * height.toInt());

    var angle = math.pi / 2 - rotationX;
    final sinx = math.sin(angle);
    final cosx = math.cos(angle);
    // angle = 0;
    // final siny = math.sin(angle);
    // final cosy = math.cos(angle);
    angle = rotationZ + math.pi / 2;
    final sinz = math.sin(angle);
    final cosz = math.cos(angle);

    //Offset rotation for selecting back of globe pixels
    final back_rotationX = -rotationX;
    angle = math.pi / 2 - back_rotationX;
    final back_sinx = math.sin(angle);
    final back_cosx = math.cos(angle);

    final backRotationZ = rotationZ + math.pi;
    angle = backRotationZ + math.pi / 2;
    final back_sinz = math.sin(angle);
    final back_cosz = math.cos(angle);

    final surfaceXRate = (surfaceWidth - 1) / (2.0 * math.pi);
    final surfaceYRate = (surfaceHeight - 1) / (math.pi);

    for (var y = minY; y < maxY; y++) {
      final sphereY = (height - y + minY - 1).toInt() * width;
      for (var x = minX; x < maxX; x++) {
        var z = r * r - x * x - y * y;
        if (z > 0) {
          z = math.sqrt(z);

          //rotate around the X axis
          double y1 = y * cosx - z * sinx;
          double z1 = y * sinx + z * cosx;
          double back_y1 = y * back_cosx - z * back_sinx;
          double back_z1 = y * back_sinx + z * back_cosx;

          //rotate around the Y axis
          // x2 = x1 * cosy + z1 * siny;
          // z2 = -x1 * siny + z1 * cosy;
          // x1 = x2;
          // z1 = z2;
          //rotate around the Z axis
          double x1 = x * cosz - y1 * sinz;
          y1 = x * sinz + y1 * cosz;
          double back_x1 = x * back_cosz - back_y1 * back_sinz;
          back_y1 = x * back_sinz + back_y1 * back_cosz;

          final lat = math.asin(z1 / r);
          final lon = math.atan2(y1, x1);

          final x0 = (lon + math.pi) * surfaceXRate;
          final y0 = (math.pi / 2 - lat) * surfaceYRate;

          final color = surface[(y0.toInt() * surfaceWidth + x0).toInt()];
          frontSpherePixels[(sphereY + x - minX).toInt()] = color;

          final back_lat = math.asin(back_z1 / r);
          final back_lon = math.atan2(back_y1, back_x1);
          final back_x0 = (back_lon + math.pi) * surfaceXRate;
          final back_y0 = (math.pi / 2 - back_lat) * surfaceYRate;

          final back_color =
              surface[(back_y0.toInt() * surfaceWidth + back_x0).toInt()];
          backSpherePixels[(sphereY + x - minX).toInt()] = back_color;
        }
      }
    }

    final c = Completer<SphereImages>();
    ui.decodeImageFromPixels(frontSpherePixels.buffer.asUint8List(),
        width.toInt(), height.toInt(), ui.PixelFormat.rgba8888, (image) {
      final frontImage = SphereImage(
        image: image,
        radius: r,
        origin: Offset(-minX, -minY),
        offset: Offset((widget.alignment.x + 1) * maxWidth / 2,
            (widget.alignment.y + 1) * maxHeight / 2),
      );

      ui.decodeImageFromPixels(backSpherePixels.buffer.asUint8List(),
          width.toInt(), height.toInt(), ui.PixelFormat.rgba8888, (image) {
        // print('widget.alignment.x: ${widget.alignment.x}');
        // print('minY: $minY');

        final backImage = SphereImage(
          image: image,
          radius: r,
          origin: Offset(-minX, -minY),
          offset: Offset((widget.alignment.x + 1) * maxWidth / 2,
              (widget.alignment.y + 1) * maxHeight / 2),
        );

        final sphereImages =
            SphereImages(frontImage: frontImage, backImage: backImage);
        c.complete(sphereImages);
      });
    });

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
    Widget mainWidgetTree = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return FutureBuilder(
          future: buildSphere(constraints.maxWidth, constraints.maxHeight),
          builder:
              (BuildContext context, AsyncSnapshot<SphereImages> snapshot) {
            return CustomPaint(
              painter: SpherePainter(
                snapshot.data,
                frontFaceColor: widget.frontFaceColor,
                backFaceColor: widget.backFaceColor,
              ),
              size: Size(constraints.maxWidth, constraints.maxHeight),
            );
          },
        );
      },
    );

    return GestureDetector(
      onScaleStart: (ScaleStartDetails details) {
        _lastZoom = zoom;
        _lastRotationX = rotationX;
        _lastRotationZ = rotationZ;
        _lastFocalPoint = details.focalPoint;
        rotationZController.stop();
      },
      onScaleUpdate: (ScaleUpdateDetails details) {
        if (widget.allowsZoom) {
          zoom = _lastZoom + math.log(details.scale) / math.ln2;
        }
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
        rotationZAnimation = Tween<double>(begin: rotationZ, end: rotationZ + s)
            .animate(CurveTween(curve: Curves.decelerate)
                .animate(rotationZController));
        rotationZController
          ..value = 0
          ..forward();
      },
      child: mainWidgetTree,
    );
  }
}

class SphereImage {
  SphereImage({this.image, this.radius, this.origin, this.offset});
  final ui.Image image;
  final double radius;
  final Offset origin;
  final Offset offset;
}

class SphereImages {
  SphereImages({this.frontImage, this.backImage});
  final SphereImage frontImage;
  final SphereImage backImage;
}

class SpherePainter extends CustomPainter {
  SpherePainter(
    this.sphereImages, {
    Color frontFaceColor,
    Color backFaceColor,
  })  : bfPainter = Paint()
          ..blendMode = BlendMode.hardLight
          ..colorFilter = ColorFilter.mode(backFaceColor, BlendMode.srcATop),
        ffPainter = Paint()
          ..colorFilter = ColorFilter.mode(frontFaceColor, BlendMode.srcATop);
  final SphereImages sphereImages;

  final Paint bfPainter;
  final Paint ffPainter;

  @override
  void paint(Canvas canvas, Size size) {
    if (sphereImages == null) return;

    final rect = Rect.fromCircle(
        center: sphereImages.frontImage.offset,
        radius: sphereImages.frontImage.radius - 1);
    final path = Path.combine(PathOperation.intersect, Path()..addOval(rect),
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)));
    canvas.clipPath(path);
    // draw back

    canvas.save();
    // canvas.scale(-1.0, 1.0);
    // canvas.translate(size.width / 2, 0);
    // final mat4InvertedX = Matrix4.identity()..scale(-1.0, 1.0)..translate(0.0, 0.0);
    // canvas.transform(mat4InvertedX.storage);

    final double dx = -(0 + size.width / 2.0);
    canvas.translate(-dx, 0.0);
    canvas.scale(-1.0, 1.0);
    canvas.translate(dx, 0.0);

    canvas.drawImage(
        sphereImages.backImage.image,
        sphereImages.backImage.offset - sphereImages.backImage.origin,
        bfPainter);
    canvas.restore();
    // draw front
    canvas.drawImage(
        sphereImages.frontImage.image,
        sphereImages.frontImage.offset - sphereImages.frontImage.origin,
        ffPainter);

    final gradientPainter = Paint();
    final gradient = RadialGradient(
      center: Alignment.center,
      colors: [
        Colors.transparent,
        Colors.black.withOpacity(0.35),
        Colors.black.withOpacity(0.5)
      ],
      stops: [0.1, 0.85, 1.0],
    );
    gradientPainter.shader = gradient.createShader(rect);
    canvas.drawRect(rect, gradientPainter);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}
