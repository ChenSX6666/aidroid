import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'log_service.dart';

class OCRBlock {
  final String text;
  final int left;
  final int top;
  final int right;
  final int bottom;
  final int cx;
  final int cy;
  final double? confidence;

  const OCRBlock({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.cx,
    required this.cy,
    this.confidence,
  });
}

class OCRService {
  static final _recognizer = TextRecognizer();

  /// Run OCR on a screenshot file path. Returns detected text blocks.
  static Future<List<OCRBlock>> recognizeFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return [];

      final inputImage = InputImage.fromFilePath(filePath);
      final result = await _recognizer.processImage(inputImage);
      return _extractBlocks(result);
    } catch (e) {
      LogService.error('OCR 失败: $e');
      return [];
    }
  }

  static List<OCRBlock> _extractBlocks(RecognizedText result) {
    final blocks = <OCRBlock>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final rect = line.boundingBox;
        final text = line.text.trim();
        if (rect == null || text.isEmpty) continue;
        if (text.length > 50) continue; // skip long paragraphs

        blocks.add(OCRBlock(
          text: text,
          left: rect.left.toInt(),
          top: rect.top.toInt(),
          right: rect.right.toInt(),
          bottom: rect.bottom.toInt(),
          cx: ((rect.left + rect.right) / 2).toInt(),
          cy: ((rect.top + rect.bottom) / 2).toInt(),
          confidence: line.confidence,
        ));
      }
    }
    return blocks;
  }

  static Future<void> dispose() async {
    await _recognizer.close();
  }
}
