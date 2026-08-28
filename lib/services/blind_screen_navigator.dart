import 'phone_control_service.dart';
import 'ui_tree_parser.dart';
import 'ocr_service.dart';
import 'vision_service.dart';
import 'log_service.dart';

class BlindScreenNavigator {
  static Set<String>? _previousOcrTexts;
  static String? _lastChangeDescription;

  // OCR result cache (2 second TTL for adjacent steps)
  static List<OCRBlock>? _cachedBlocks;
  static DateTime? _cacheTime;
  static const _cacheTtl = Duration(seconds: 2);

  static List<OCRBlock>? getCachedOcrBlocks() {
    if (_cachedBlocks != null && _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheTtl) {
      return _cachedBlocks;
    }
    return null;
  }

  static void cacheOcrBlocks(List<OCRBlock> blocks) {
    _cachedBlocks = blocks;
    _cacheTime = DateTime.now();
  }

  /// Detect if the current screen is a "blind screen" (Unity, WebGL, game engine)
  static bool isBlind(String xml) {
    if (!xml.contains('<?xml')) return true;
    final elements = UITreeParser.parse(xml);
    return elements.length < 3;
  }

  /// Track OCR text for change detection across agent steps.
  static void trackOcrForChange(List<OCRBlock> blocks) {
    final currentTexts = blocks.map((b) => b.text).toSet();
    final last = _previousOcrTexts;
    _previousOcrTexts = currentTexts;

    if (last == null) {
      _lastChangeDescription = '首次盲屏视觉分析，检测到 ${blocks.length} 个文字区域';
    } else if (currentTexts.isEmpty && last.isEmpty) {
      _lastChangeDescription = '盲屏无文字，无法检测变化';
    } else {
      final newTexts = currentTexts.difference(last);
      final removedTexts = last.difference(currentTexts);
      if (newTexts.isEmpty && removedTexts.isEmpty) {
        _lastChangeDescription = '盲屏OCR文字无变化';
      } else {
        final buf = StringBuffer('盲屏变化: ');
        if (newTexts.isNotEmpty) buf.write('+${newTexts.take(3).join(",")} ');
        if (removedTexts.isNotEmpty) buf.write('-${removedTexts.take(3).join(",")}');
        _lastChangeDescription = buf.toString();
      }
    }
  }

  static String? get lastChangeDescription => _lastChangeDescription;

  static void resetBlindTracking() {
    _previousOcrTexts = null;
    _lastChangeDescription = null;
  }

  /// Build an enhanced screen description for blind screens.
  static Future<String> buildVisualReport({
    required String xml,
    required String displaySize,
    void Function(String?)? onStatus,
  }) async {
    if (!isBlind(xml)) {
      return UITreeParser.buildScreenDescription(xml, displaySize);
    }

    LogService.info('检测到盲屏(UI树元素<3)，启用视觉理解');
    onStatus?.call('🖼️ 检测盲屏，启用视觉理解...');

    try {
      final res = VisionService.parseDisplay(displaySize);

      final shotPath = await PhoneControlService.captureScreenshot();
      onStatus?.call('📸 截图完成 (${res.w}x${res.h})');

      // Run OCR and visual analysis (Gemini/ML Kit) in parallel
      // Use cached OCR if fresh enough
      final cachedOcr = getCachedOcrBlocks();
      final results = await Future.wait([
        cachedOcr != null
            ? Future.value(cachedOcr)
            : OCRService.recognizeFile(shotPath).catchError((_) => <OCRBlock>[]),
        VisionService.buildVisualReport(
          screenshotPath: shotPath,
          ocrBlocks: const [],
          displaySize: displaySize,
          onStatus: onStatus,
        ).catchError((_) => ''),
      ]);

      final ocrBlocks = results[0] as List<OCRBlock>;
      if (cachedOcr == null && ocrBlocks.isNotEmpty) cacheOcrBlocks(ocrBlocks);
      var visualReport = results[1] as String;

      // Track OCR for change detection
      trackOcrForChange(ocrBlocks);

      // Merge OCR spatial analysis if not already present
      if (ocrBlocks.isNotEmpty && !visualReport.contains('OCR 空间布局')) {
        visualReport = '$visualReport\n${VisionService.buildSpatialAnalysis(ocrBlocks, displaySize)}';
      }

      final buf = StringBuffer();
      buf.writeln('屏幕: $displaySize');
      buf.writeln('⚠️ 盲屏模式 — 全屏渲染视图(Unity/游戏/WebGL)，UI树不可用');
      buf.writeln();
      buf.writeln(visualReport);
      buf.writeln();
      buf.writeln('操作提示: 所有交互需使用坐标 tap(不要用 target #N)。');
      buf.writeln('格式: {"action":"tap","x":${res.w ~/ 2},"y":${(res.h * 0.45).toInt()},"reason":"点击主操作区域"}');

      return buf.toString();
    } catch (e) {
      LogService.error('盲屏视觉报告失败: $e');
      // Ultimate fallback with dynamic coordinates
      final res = VisionService.parseDisplay(displaySize);
      final elements = UITreeParser.parse(xml);
      final buf = StringBuffer();
      buf.writeln('屏幕: $displaySize');
      buf.writeln('⚠️ 盲屏模式 — UI树仅 ${elements.length} 个元素');
      buf.writeln();
      buf.writeln('[策略] 尝试常见位置:');
      buf.writeln('  屏幕中央: tap(${res.w ~/ 2},${(res.h * 0.4).toInt()}) — 主按钮常用位置');
      buf.writeln('  右上角: tap(${(res.w * 0.92).toInt()},${(res.h * 0.08).toInt()}) — 关闭/跳过按钮');
      buf.writeln('  左上角: tap(${(res.w * 0.08).toInt()},${(res.h * 0.08).toInt()}) — 返回按钮');
      buf.writeln('  向下滑动: swipe(${res.w ~/ 2},${(res.h * 0.67).toInt()},${res.w ~/ 2},${(res.h * 0.33).toInt()}) — 可能触发动画或翻页');
      buf.writeln();
      buf.writeln('请直接输出坐标操作。');
      return buf.toString();
    }
  }
}
