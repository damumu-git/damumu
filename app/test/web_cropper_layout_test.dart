import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:zaihandazi/web_cropper_layout.dart';

void main() {
  test('uses a page for a 320px device-toolbar viewport', () {
    final layout = webCropperLayoutFor(const Size(320, 761));

    expect(layout.presentStyle, WebPresentStyle.page);
    expect(layout.size.width, 288);
    expect(layout.size.height, 520);
  });

  test('keeps the cropper within a short landscape viewport', () {
    final layout = webCropperLayoutFor(const Size(761, 320));

    expect(layout.presentStyle, WebPresentStyle.page);
    expect(layout.size.height, 144);
  });

  test('keeps the desktop dialog layout and caps its canvas', () {
    final layout = webCropperLayoutFor(const Size(1440, 900));

    expect(layout.presentStyle, WebPresentStyle.dialog);
    expect(layout.size.width, 720);
    expect(layout.size.height, 520);
  });
}
