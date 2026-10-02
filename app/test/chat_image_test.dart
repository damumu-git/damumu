import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zaihandazi/chat_image.dart';
import 'package:zaihandazi/main.dart';

void main() {
  test('chat images are resized and compressed on the client', () async {
    final source = img.Image(width: 1800, height: 1350, numChannels: 4);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgba(x, y, x % 256, y % 256, (x + y) % 256, 180);
      }
    }

    final compressed = await compressChatImage(
      Uint8List.fromList(img.encodePng(source)),
    );
    final decoded = img.decodeJpg(compressed);

    expect(decoded, isNotNull);
    expect(decoded!.width, 1600);
    expect(decoded.height, 1200);
    expect(decoded.numChannels, 3);
    expect(compressed.length, lessThanOrEqualTo(chatImageTargetBytes));
  });

  test('unsupported bytes are rejected before upload', () async {
    await expectLater(
      compressChatImage(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(isA<FormatException>()),
    );
  });

  testWidgets('chat image preview supports pinch zoom', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ChatImagePreviewPage(
          imageUrl: 'https://example.invalid/image.jpg',
        ),
      ),
    );

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('View image'), findsOneWidget);
  });
}
