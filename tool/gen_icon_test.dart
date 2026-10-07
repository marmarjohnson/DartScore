// Run with:  flutter test tool/gen_icon_test.dart
// Renders the app icon to a 1024×1024 PNG and saves it to
// assets/icon/app_icon.png, ready for flutter_launcher_icons.
//
// WARNING: this does not draw the icon the app currently ships. The painter
// below renders a plain board with "180+" across the middle, while the
// committed assets/icon/app_icon.png is a "DartScore" wordmark over a board
// with a dart in it. Running this replaces the shipped icon with the older
// artwork. Bring the painter in step with the shipped design before using it.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dartscore_app/widgets/dartboard_icon.dart';

void main() {
  testWidgets('export dartboard as app icon PNG', (WidgetTester tester) async {
    const size = 1024.0;

    // ── Load the font the "180+" is drawn in ──────────────────────────────
    // Roboto Black Italic ships inside the Flutter SDK, so every machine that
    // can run this tool renders the same icon. Reading a macOS system font
    // instead made the output depend on the host: where those fonts are
    // absent nothing loaded, the test font drew every glyph as a filled box,
    // and the tool still overwrote the PNG and passed.
    final fontFile = materialFont('Roboto-BlackItalic.ttf');
    if (fontFile == null) {
      fail('Roboto-BlackItalic.ttf was not found in the Flutter SDK. Run '
          '`flutter precache` to fetch the material fonts, or set FLUTTER_ROOT '
          'to the SDK this tool should read them from.');
    }
    final loader = FontLoader(iconFontFamily)
      ..addFont(Future.value(ByteData.sublistView(fontFile.readAsBytesSync())));
    await loader.load();

    // Give the test canvas enough room
    tester.view.physicalSize = const Size(size, size);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.expand(
            child: RepaintBoundary(
              child: Container(
                width: size,
                height: size,
                color: Colors.black,
                alignment: Alignment.center,
                child: CustomPaint(
                  size: const Size(size, size),
                  painter: const _AppIconPainter(fontFamily: iconFontFamily),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final outFile = File('assets/icon/app_icon.png');
    outFile.writeAsBytesSync(pngBytes);

    // ignore: avoid_print
    print('✅  Icon saved to ${outFile.absolute.path}  (${pngBytes.length} bytes)');
    expect(pngBytes.length, greaterThan(1000));
  });
}

/// Black background + dartboard (scaled, centred slightly high) +
/// bold "180" in red with a thick black outline at the bottom.
class _AppIconPainter extends CustomPainter {
  /// Family the "180+" is drawn in, registered by the test before painting.
  final String fontFamily;

  /// Creates the painter, drawing its text in [fontFamily].
  const _AppIconPainter({required this.fontFamily});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // ── Black background ──────────────────────────────────────────────────
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);

    // ── Dartboard — full size, centred ────────────────────────────────────
    final boardSize = size.width * 0.92;
    final boardTop  = cy - boardSize / 2;
    canvas.save();
    canvas.translate(cx - boardSize / 2, boardTop);
    DartboardPainter().paint(canvas, Size(boardSize, boardSize));
    canvas.restore();

    // ── "180+" italic, centred on the bull ───────────────────────────────
    final fontSize = size.width * 0.27;
    // vertically centred on the board centre
    final textY = cy - fontSize * 0.60;

    void drawText(ui.Canvas c, String text, Color color, double strokeWidth) {
      final style = ui.TextStyle(
        color: strokeWidth == 0 ? color : null,
        foreground: strokeWidth > 0
            ? (Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..strokeJoin = StrokeJoin.round
              ..color = color)
            : null,
        fontSize: fontSize,
        fontWeight: ui.FontWeight.w900,
        fontStyle: ui.FontStyle.italic,
        fontFamily: fontFamily,
      );
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: ui.TextAlign.center,
        fontWeight: ui.FontWeight.w900,
        fontStyle: ui.FontStyle.italic,
        fontSize: fontSize,
        fontFamily: fontFamily,
      ))
        ..pushStyle(style)
        ..addText(text);
      final para = pb.build()
        ..layout(ui.ParagraphConstraints(width: size.width));
      c.drawParagraph(para, Offset(0, textY));
    }

    // 1. Thick black stroke (outline)
    drawText(canvas, '180+', Colors.black, fontSize * 0.18);
    // 2. Red fill on top
    drawText(canvas, '180+', const Color(0xFFD32F2F), 0);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Family name the icon font is registered under.
const iconFontFamily = '_IconFont';

/// Locates [name] among the material fonts bundled with the Flutter SDK.
///
/// Checks `FLUTTER_ROOT` first, then walks up from the running Dart
/// executable, which sits under `<sdk>/bin/cache/dart-sdk/bin`, taking the
/// first ancestor that holds the material font cache. Walking rather than
/// counting directories keeps this working if the SDK layout shifts. Returns
/// null when no candidate holds the cache, which is what a checkout that has
/// never been precached looks like.
File? materialFont(String name) {
  final roots = <String>[];
  final fromEnv = Platform.environment['FLUTTER_ROOT'];
  if (fromEnv != null) roots.add(fromEnv);
  roots.addAll(ancestorsOf(Platform.resolvedExecutable));
  for (final root in roots) {
    final file = File(p.join(root, 'bin', 'cache', 'artifacts',
                             'material_fonts', name));
    if (file.existsSync()) return file;
  }
  return null;
}

/// Every ancestor directory of [path], nearest first.
Iterable<String> ancestorsOf(String path) sync* {
  var dir = p.dirname(path);
  while (true) {
    yield dir;
    final parent = p.dirname(dir);
    if (parent == dir) return;
    dir = parent;
  }
}
