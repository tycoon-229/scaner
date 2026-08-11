import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CameraScannerOverlayBorder
// ─────────────────────────────────────────────────────────────────────────────

/// A [ShapeBorder] that draws the classic scanner overlay.
///
/// The rendering is a **direct port** of `ScannerOverlayBorder.paint()`
/// from the `flutter_zxing` library:
///
/// 1. The full screen is filled with [overlayColor] via `drawPath(outerPath)`.
/// 2. A `saveLayer` is opened and the same background is drawn with `drawRect`.
/// 3. Four `drawRRect` strokes paint the L-shaped corner brackets.
/// 4. A final `drawRRect` with `BlendMode.dstOut` punches a transparent
///    rectangular hole — revealing the live camera preview underneath.
/// 5. `restore()` composites the layer onto the screen.
///
/// ### Key parameters
/// * [cutOutSize] — `> 1` → absolute pixels; `<= 1` → fraction of shorter side.
/// * [horizontalOffset] / [verticalOffset] — shift centre (−1.0 … 1.0).
/// * [borderLength] — arm length of each corner bracket (clamped to `cutOut/2`).
/// * [borderWidth]  — stroke width of corner brackets.
/// * [borderRadius] — corner radius applied to both cutout rect and brackets.
/// * [overlayColor] — dark vignette fill. Defaults to [Colors.black45].
/// * [borderColor]  — corner bracket colour. Defaults to [Colors.white].
class CameraScannerOverlayBorder extends ShapeBorder {
  const CameraScannerOverlayBorder({
    this.cutOutSize = 250,
    this.horizontalOffset = 0,
    this.verticalOffset = 0,
    this.borderColor = Colors.white,
    this.borderWidth = 4,
    this.overlayColor = Colors.black45,
    this.borderRadius = 16,
    this.borderLength = 32,
  });

  /// `> 1` → pixels; `<= 1` → fraction of the shorter screen side.
  final double cutOutSize;

  /// Horizontal offset of cut-out centre. Range: −1.0 … 1.0.
  final double horizontalOffset;

  /// Vertical offset of cut-out centre. Range: −1.0 … 1.0.
  final double verticalOffset;

  /// Colour of the four corner bracket strokes.
  final Color borderColor;

  /// Stroke width of the corner brackets.
  final double borderWidth;

  /// Colour of the dark overlay surrounding the cut-out.
  final Color overlayColor;

  /// Corner radius of both the cut-out rect and the bracket corners.
  final double borderRadius;

  /// Length of each corner bracket arm (clamped to `cutOut / 2`).
  final double borderLength;

  // ── Internal helpers ────────────────────────────────────────────────────────

  /// Computes the cut-out [Rect] — mirrors zxing calculation exactly.
  Rect _cutOutRect(Rect rect) {
    final double width = rect.width;
    final double height = rect.height;

    final double cutOut = cutOutSize > 1
        ? cutOutSize.clamp(0.0, width < height ? width : height)
        : (width < height ? width : height) * cutOutSize;

    final double dx = horizontalOffset * ((width - cutOut) / 2);
    final double dy = verticalOffset * ((height - cutOut) / 2);

    return Rect.fromLTWH(
      width / 2 - cutOut / 2 + dx,
      height / 2 - cutOut / 2 + dy,
      cutOut,
      cutOut,
    );
  }

  // ── ShapeBorder overrides ───────────────────────────────────────────────────

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  ShapeBorder scale(double t) => this;

  @override
  ShapeBorder lerpFrom(ShapeBorder? a, double t) => this;

  @override
  ShapeBorder lerpTo(ShapeBorder? b, double t) => this;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    final Rect co = _cutOutRect(rect);
    return Path()
      ..addRRect(RRect.fromRectAndRadius(co, Radius.circular(borderRadius)));
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final Path outer = Path()..addRect(rect);
    final Rect co = _cutOutRect(rect);
    final Path cutPath = Path()
      ..addRRect(RRect.fromRectAndRadius(co, Radius.circular(borderRadius)));
    return Path.combine(PathOperation.difference, outer, cutPath);
  }

  // ── paint() ─────────────────────────────────────────────────────────────────
  // Direct port of ScannerOverlayBorder.paint() from flutter_zxing.
  // ───────────────────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final double width = rect.width;
    final double height = rect.height;

    // Resolve cutout size
    final double cutOut = cutOutSize > 1
        ? cutOutSize.clamp(0.0, width < height ? width : height)
        : (width < height ? width : height) * cutOutSize;

    final double dx = horizontalOffset * ((width - cutOut) / 2);
    final double dy = verticalOffset * ((height - cutOut) / 2);

    final Rect cutOutRect = Rect.fromLTWH(
      width / 2 - cutOut / 2 + dx,
      height / 2 - cutOut / 2 + dy,
      cutOut,
      cutOut,
    );

    // ── Step 1: fill the area outside the cutout with overlayColor ────────
    final Paint overlayPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(getOuterPath(rect), overlayPaint);

    // ── Step 2: corner bracket stroke paint ───────────────────────────────
    final Paint borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round;

    // Clamp arm length so brackets don't overlap at the centre
    final double newBorderLength = borderLength.clamp(0.0, cutOut / 2);

    // ── Step 3: saveLayer — compose brackets + transparent cutout ─────────
    final Paint backgroundPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    // dstOut blends by treating the alpha of the source as an eraser
    final Paint boxPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.dstOut;

    canvas
      ..saveLayer(rect, backgroundPaint)
      ..drawRect(rect, backgroundPaint)

      // Top-right corner bracket
      ..drawRRect(
        RRect.fromLTRBAndCorners(
          cutOutRect.right - newBorderLength,
          cutOutRect.top,
          cutOutRect.right,
          cutOutRect.top + newBorderLength,
          topRight: Radius.circular(borderRadius),
        ),
        borderPaint,
      )

      // Top-left corner bracket
      ..drawRRect(
        RRect.fromLTRBAndCorners(
          cutOutRect.left,
          cutOutRect.top,
          cutOutRect.left + newBorderLength,
          cutOutRect.top + newBorderLength,
          topLeft: Radius.circular(borderRadius),
        ),
        borderPaint,
      )

      // Bottom-right corner bracket
      ..drawRRect(
        RRect.fromLTRBAndCorners(
          cutOutRect.right - newBorderLength,
          cutOutRect.bottom - newBorderLength,
          cutOutRect.right,
          cutOutRect.bottom,
          bottomRight: Radius.circular(borderRadius),
        ),
        borderPaint,
      )

      // Bottom-left corner bracket
      ..drawRRect(
        RRect.fromLTRBAndCorners(
          cutOutRect.left,
          cutOutRect.bottom - newBorderLength,
          cutOutRect.left + newBorderLength,
          cutOutRect.bottom,
          bottomLeft: Radius.circular(borderRadius),
        ),
        borderPaint,
      )

      // Punch the transparent cutout window through the overlay layer
      ..drawRRect(
        RRect.fromRectAndRadius(cutOutRect, Radius.circular(borderRadius)),
        boxPaint,
      )

      ..restore();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ScannerScanLine — animated scan line inside the viewfinder cut-out
// ─────────────────────────────────────────────────────────────────────────────

/// An animated horizontal scan-line that bounces inside the viewfinder cut-out.
///
/// Position this widget over the cut-out area (e.g. with [Positioned])
/// sized to exactly the cut-out dimensions.
class ScannerScanLine extends StatefulWidget {
  const ScannerScanLine({
    super.key,
    this.lineColor = const Color(0xFF00E5FF),
    this.lineWidth = 2.5,
    this.glowRadius = 8.0,
    this.duration = const Duration(seconds: 2),
  });

  /// Primary colour of the scan line.
  final Color lineColor;

  /// Thickness of the scan line stroke.
  final double lineWidth;

  /// Blur radius for the glow halo (0 to disable).
  final double glowRadius;

  /// Duration of one full bounce cycle.
  final Duration duration;

  @override
  State<ScannerScanLine> createState() => _ScannerScanLineState();
}

class _ScannerScanLineState extends State<ScannerScanLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (BuildContext context, _) {
        return CustomPaint(
          painter: _ScanLinePainter(
            progress: _animation.value,
            color: widget.lineColor,
            lineWidth: widget.lineWidth,
            glowRadius: widget.glowRadius,
          ),
        );
      },
    );
  }
}

class _ScanLinePainter extends CustomPainter {
  const _ScanLinePainter({
    required this.progress,
    required this.color,
    required this.lineWidth,
    required this.glowRadius,
  });

  final double progress;
  final Color color;
  final double lineWidth;
  final double glowRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final double y = progress * size.height;

    // Soft glow halo
    if (glowRadius > 0) {
      final Paint glowPaint = Paint()
        ..color = color.withValues(alpha: 0.35)
        ..strokeWidth = lineWidth + glowRadius * 2
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius)
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), glowPaint);
    }

    // Solid scan line
    final Paint linePaint = Paint()
      ..color = color
      ..strokeWidth = lineWidth
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.lineWidth != lineWidth ||
      old.glowRadius != glowRadius;
}
