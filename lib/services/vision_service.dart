import 'ocr_service.dart';
import 'image_label_service.dart';

class VisionService {
  /// Get visual tier: 1=ML Kit image labeling, 2=OCR only
  static Future<int> visualTier() async {
    if (ImageLabelService.isAvailable) return 1;
    return 2;
  }

  /// Parse display resolution from "1080x2400" format
  static ({int w, int h}) parseDisplay(String displaySize) {
    final m = RegExp(r'(\d+)x(\d+)').firstMatch(displaySize);
    if (m != null) {
      return (w: int.parse(m.group(1)!), h: int.parse(m.group(2)!));
    }
    return (w: 1080, h: 2400);
  }

  /// Generate a complete visual report for a screenshot
  /// ML Kit provides on-device image labeling, OCR provides text positions
  static Future<String> buildVisualReport({
    required String screenshotPath,
    required List<OCRBlock> ocrBlocks,
    required String displaySize,
    void Function(String?)? onStatus,
  }) async {
    final tier = await visualTier();
    final tierNames = {1: 'ML Kit 图像标签 (L1)', 2: '纯 OCR (L2)'};
    final parts = <String>[];

    parts.add('[视觉层级: ${tierNames[tier] ?? "未知"}]');

    if (tier == 1) {
      onStatus?.call('ML Kit 分析中...');
      final labels = await ImageLabelService.labelFile(screenshotPath);
      if (labels.isNotEmpty) {
        final summary = ImageLabelService.describe(labels);
        if (summary.isNotEmpty) {
          onStatus?.call('ML Kit: $summary');
          parts.add('[ML Kit 图像标签 (L1)] $summary');
          parts.add('');
        }
      }
    }

    // OCR spatial analysis (always available)
    if (ocrBlocks.isNotEmpty) {
      onStatus?.call('OCR: ${ocrBlocks.length} 个文字区域');
    } else {
      onStatus?.call('OCR: 无文字区域 (盲屏)');
    }
    if (ocrBlocks.isNotEmpty) {
      parts.add(buildSpatialAnalysis(ocrBlocks, displaySize));
    }

    if (parts.length <= 1) {
      final res = parseDisplay(displaySize);
      parts.add('[盲屏] 无可交互 UI 元素，且未检测到可见文字。');
      parts.add('尝试: 点击屏幕中央(${res.w ~/ 2},${(res.h * 0.4).toInt()})、滑动页面、或等待加载完成。');
    } else {
      parts.add('[策略] 优先点击中央区域带文字的位置作为主操作目标。');
      parts.add('2次无响应后尝试滑动或点击其他区域。');
    }

    if (tier == 1) {
      parts.add('[层级说明] ML Kit 提供本地场景分类 + OCR 坐标定位');
    } else {
      parts.add('[层级说明] 仅 OCR 文字检测，无画面理解，需依赖坐标试探');
    }

    return parts.join('\n');
  }

  /// Build spatial analysis from OCR blocks
  static String buildSpatialAnalysis(List<OCRBlock> blocks, String displaySize) {
    final parts = <String, List<OCRBlock>>{};
    final h = _parseHeight(displaySize);

    for (final b in blocks) {
      String zone;
      if (b.cy < h * 0.2) {
        zone = '顶部';
      } else if (b.cy > h * 0.75) {
        zone = '底部';
      } else {
        zone = '中央';
      }
      parts.putIfAbsent(zone, () => []).add(b);
    }

    final buf = StringBuffer();
    buf.writeln('[OCR 空间布局] (屏幕: $displaySize)');

    for (final zone in ['顶部', '中央', '底部']) {
      final items = parts[zone];
      if (items == null || items.isEmpty) continue;
      buf.writeln('$zone区域:');
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final confStr = item.confidence != null ? ' [${(item.confidence! * 100).toInt()}%]' : '';
        buf.writeln('  "${item.text}" @(${item.cx},${item.cy})$confStr');
      }
    }

    return buf.toString();
  }

  static int _parseHeight(String displaySize) {
    final m = RegExp(r'(\d+)x(\d+)').firstMatch(displaySize);
    if (m != null) return int.tryParse(m.group(2)!) ?? 2400;
    return 2400;
  }
}
