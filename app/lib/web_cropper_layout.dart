import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';

const _compactWidthBreakpoint = 600.0;
const _compactHeightBreakpoint = 820.0;

class WebCropperLayout {
  const WebCropperLayout({required this.presentStyle, required this.size});

  final WebPresentStyle presentStyle;
  final CropperSize size;
}

WebCropperLayout webCropperLayoutFor(Size viewport) {
  final compact =
      viewport.width < _compactWidthBreakpoint ||
      viewport.height < _compactHeightBreakpoint;
  if (compact) {
    return WebCropperLayout(
      presentStyle: WebPresentStyle.page,
      size: CropperSize(
        width: (viewport.width - 32).clamp(160, 720).round(),
        height: (viewport.height - 176).clamp(100, 520).round(),
      ),
    );
  }
  return WebCropperLayout(
    presentStyle: WebPresentStyle.dialog,
    size: CropperSize(
      width: (viewport.width - 128).clamp(320, 720).round(),
      height: (viewport.height - 240).clamp(100, 520).round(),
    ),
  );
}

WebCropperLayout webCropperLayout(BuildContext context) =>
    webCropperLayoutFor(MediaQuery.sizeOf(context));
