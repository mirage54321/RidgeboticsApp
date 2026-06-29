import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'constants.dart';

class CropRegion {
  final double x;
  final double y;
  final double width;
  final double height;

  const CropRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory CropRegion.fromRegionName(String region) {
    switch (region) {
      case 'top-left':
        return const CropRegion(x: 0.0, y: 0.0, width: 0.55, height: 0.55);
      case 'top-center':
        return const CropRegion(x: 0.25, y: 0.0, width: 0.5, height: 0.5);
      case 'top-right':
        return const CropRegion(x: 0.45, y: 0.0, width: 0.55, height: 0.55);
      case 'middle-left':
        return const CropRegion(x: 0.0, y: 0.25, width: 0.55, height: 0.5);
      case 'center':
        return const CropRegion(x: 0.2, y: 0.2, width: 0.6, height: 0.6);
      case 'middle-right':
        return const CropRegion(x: 0.45, y: 0.25, width: 0.55, height: 0.5);
      case 'bottom-left':
        return const CropRegion(x: 0.0, y: 0.45, width: 0.55, height: 0.55);
      case 'bottom-center':
        return const CropRegion(x: 0.25, y: 0.5, width: 0.5, height: 0.5);
      case 'bottom-right':
        return const CropRegion(x: 0.45, y: 0.45, width: 0.55, height: 0.55);
      default:
        return const CropRegion(x: 0.0, y: 0.0, width: 1.0, height: 1.0);
    }
  }
}

class CroppedImage {
  final String base64Jpeg;
  final CropRegion region;

  const CroppedImage({required this.base64Jpeg, required this.region});
}

CroppedImage cropToRegion(Uint8List originalBytes, CropRegion region) {
  final decoded = img.decodeImage(originalBytes);
  if (decoded == null) {
    return CroppedImage(
      base64Jpeg: base64Encode(originalBytes),
      region: const CropRegion(x: 0.0, y: 0.0, width: 1.0, height: 1.0),
    );
  }

  final cropX = (region.x * decoded.width).round().clamp(0, decoded.width - 1);
  final cropY =
      (region.y * decoded.height).round().clamp(0, decoded.height - 1);
  final cropW =
      (region.width * decoded.width).round().clamp(1, decoded.width - cropX);
  final cropH = (region.height * decoded.height)
      .round()
      .clamp(1, decoded.height - cropY);

  final cropped = img.copyCrop(
    decoded,
    x: cropX,
    y: cropY,
    width: cropW,
    height: cropH,
  );

  final jpegBytes = img.encodeJpg(cropped, quality: 85);

  return CroppedImage(
    base64Jpeg: base64Encode(jpegBytes),
    region: region,
  );
}

BoundingBox? mapBoxFromCropToFull(
  List<dynamic>? box2dInCrop,
  CropRegion region,
) {
  if (box2dInCrop == null || box2dInCrop.length != 4) return null;

  final cropBox = BoundingBox.fromBox2D(box2dInCrop);

  return BoundingBox(
    x: region.x + cropBox.x * region.width,
    y: region.y + cropBox.y * region.height,
    width: cropBox.width * region.width,
    height: cropBox.height * region.height,
  );
}