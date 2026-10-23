import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playra/screens/player/widgets/dual_subtitle_view.dart';

void main() {
  const style = TextStyle(fontSize: 30, color: Color(0xFFFFFF00));

  Future<void> pump(WidgetTester tester, DualSubtitleView view) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: view));
  }

  DualSubtitleView view({
    String secondaryPosition = 'below',
    String horizontalAlign = 'center',
    double horizontalOffset = 0,
    bool showSecondary = true,
    BitmapSubtitleRole bitmapRole = BitmapSubtitleRole.none,
  }) => DualSubtitleView(
    subtitles: const Stream<List<String>>.empty(),
    initialSubtitles: const ['Ahoj', 'Hello'],
    style: style,
    showSecondary: showSecondary,
    secondaryScale: 0.5,
    secondaryColor: const Color(0xFF00FFFF),
    secondaryPosition: secondaryPosition,
    horizontalAlign: horizontalAlign,
    horizontalOffset: horizontalOffset,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
    bitmapRole: bitmapRole,
    videoSize: const Size(1920, 1080),
  );

  Rect rectOf(WidgetTester tester, String text) => tester.getRect(find.text(text));

  testWidgets('the secondary line is smaller, in its own colour, below the main one', (tester) async {
    await pump(tester, view());

    final main = tester.widget<Text>(find.text('Ahoj'));
    final secondary = tester.widget<Text>(find.text('Hello'));
    expect(main.style!.fontSize, 30);
    expect(secondary.style!.fontSize, 15);
    expect(secondary.style!.color, const Color(0xFF00FFFF));
    expect(rectOf(tester, 'Hello').top, greaterThanOrEqualTo(rectOf(tester, 'Ahoj').bottom));
    expect(rectOf(tester, 'Hello').bottom, closeTo(1080 - 32, 1));
  });

  testWidgets('the secondary line can go above the main one or to the top of the screen', (tester) async {
    await pump(tester, view(secondaryPosition: 'above'));
    expect(rectOf(tester, 'Hello').bottom, lessThanOrEqualTo(rectOf(tester, 'Ahoj').top));
    expect(rectOf(tester, 'Ahoj').bottom, closeTo(1080 - 32, 1));

    await pump(tester, view(secondaryPosition: 'top'));
    expect(rectOf(tester, 'Hello').top, lessThan(100));
    expect(rectOf(tester, 'Ahoj').bottom, closeTo(1080 - 32, 1));
  });

  testWidgets('both lines follow the alignment and the sideways shift', (tester) async {
    await pump(tester, view(horizontalAlign: 'left'));
    expect(rectOf(tester, 'Ahoj').left, closeTo(16, 1));
    expect(tester.widget<Text>(find.text('Ahoj')).textAlign, TextAlign.left);

    await pump(tester, view(horizontalAlign: 'right'));
    expect(rectOf(tester, 'Ahoj').right, closeTo(1920 - 16, 1));

    await pump(tester, view());
    final centred = rectOf(tester, 'Ahoj').center.dx;
    await pump(tester, view(horizontalOffset: 0.25));
    expect(rectOf(tester, 'Ahoj').center.dx, closeTo(centred + 0.25 * 1920, 1));
  });

  testWidgets('a picture-based track hides its own line', (tester) async {
    await pump(tester, view(bitmapRole: BitmapSubtitleRole.primary));
    expect(find.text('Ahoj'), findsNothing);
    expect(find.text('Hello'), findsOneWidget);

    await pump(tester, view(bitmapRole: BitmapSubtitleRole.secondary));
    expect(find.text('Ahoj'), findsOneWidget);
    expect(find.text('Hello'), findsNothing);
    // Lifted above the band where mpv draws the picture-based secondary track.
    expect(rectOf(tester, 'Ahoj').bottom, lessThan(1080 - 1080 * 0.2));
  });

  testWidgets('the secondary line stays hidden while no secondary track is on', (tester) async {
    await pump(tester, view(showSecondary: false));
    expect(find.text('Hello'), findsNothing);
  });
}
