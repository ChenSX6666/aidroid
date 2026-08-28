import 'ui_tree_parser.dart';
import 'ocr_service.dart';

class UIEnhancer {
  /// Enhance XML-based screen description with OCR-detected text blocks.
  /// OCR text matching existing XML elements enriches their labels.
  /// OCR text with no matching XML element is added as virtual [OCR] elements.
  static String enhance(String xml, List<OCRBlock> ocrBlocks, String displaySize) {
    if (ocrBlocks.isEmpty) {
      return UITreeParser.buildScreenDescription(xml, displaySize);
    }

    final elements = UITreeParser.parse(xml);
    final usedBlocks = <int>{};
    final enrichedElements = <_EnrichedElement>[];

    for (final el in elements) {
      final matchedTexts = <String>[];
      for (int i = 0; i < ocrBlocks.length; i++) {
        if (usedBlocks.contains(i)) continue;
        final block = ocrBlocks[i];
        if (_overlaps(el, block)) {
          matchedTexts.add(block.text);
          usedBlocks.add(i);
        }
      }
      enrichedElements.add(_EnrichedElement(
        element: el,
        ocrTexts: matchedTexts,
      ));
    }

    // Collect OCR-only blocks as virtual elements (not inside any existing element)
    final virtualElements = <_VirtualElement>[];
    for (int i = 0; i < ocrBlocks.length; i++) {
      if (usedBlocks.contains(i)) continue;
      final block = ocrBlocks[i];
      bool contained = false;
      for (final el in elements) {
        if (_contains(el, block)) {
          contained = true;
          break;
        }
      }
      if (!contained) {
        virtualElements.add(_VirtualElement(
          text: block.text,
          cx: block.cx,
          cy: block.cy,
          left: block.left,
          top: block.top,
          right: block.right,
          bottom: block.bottom,
        ));
      }
    }

    return _formatEnhanced(enrichedElements, virtualElements, displaySize);
  }

  /// Check if OCR block overlaps with a UI element (center containment or >30% area overlap)
  static bool _overlaps(UIElement el, OCRBlock block) {
    if (block.cx >= el.left && block.cx <= el.right &&
        block.cy >= el.top && block.cy <= el.bottom) {
      return true;
    }
    final overlapLeft = el.left > block.left ? el.left : block.left;
    final overlapTop = el.top > block.top ? el.top : block.top;
    final overlapRight = el.right < block.right ? el.right : block.right;
    final overlapBottom = el.bottom < block.bottom ? el.bottom : block.bottom;
    if (overlapLeft >= overlapRight || overlapTop >= overlapBottom) return false;
    final overlapArea = (overlapRight - overlapLeft) * (overlapBottom - overlapTop);
    final blockArea = (block.right - block.left) * (block.bottom - block.top);
    return blockArea > 0 && overlapArea > blockArea * 0.3;
  }

  /// Check if OCR block is fully contained within a UI element
  static bool _contains(UIElement el, OCRBlock block) {
    return block.left >= el.left && block.top >= el.top &&
        block.right <= el.right && block.bottom <= el.bottom;
  }

  static String _formatEnhanced(
    List<_EnrichedElement> enriched,
    List<_VirtualElement> virtuals,
    String displaySize,
  ) {
    final buf = StringBuffer();
    buf.writeln('屏幕: $displaySize');
    final totalElements = enriched.length + virtuals.length;
    buf.writeln('交互元素: $totalElements 个 (含 ${virtuals.length} 个 OCR 补充)');
    buf.writeln();

    int idx = 0;
    for (final ee in enriched) {
      final e = ee.element;
      buf.write('#$idx ${e.className}');

      String label = e.label;
      if (ee.ocrTexts.isNotEmpty) {
        final ocrExtra = ee.ocrTexts.where((t) => !label.contains(t)).toList();
        if (ocrExtra.isNotEmpty) {
          final combined = ocrExtra.join(' | ');
          label = label.isNotEmpty ? '$label [$combined]' : combined;
        }
      }

      if (label.isNotEmpty) {
        final display = label.length > 50 ? '${label.substring(0, 50)}...' : label;
        buf.write(' "$display"');
      }

      buf.write(' @(${e.cx},${e.cy})');

      if (e.resourceId.isNotEmpty) {
        buf.write(' id=${e.resourceId}');
      }

      final flags = <String>[];
      if (e.isClickable) flags.add('T');
      if (e.isLongClickable) flags.add('L');
      if (e.isScrollable) flags.add('S');
      if (e.isEditable) flags.add('E');
      if (e.isCheckable) flags.add(e.isChecked ? 'V' : 'C');
      if (e.isFocused) flags.add('F');
      if (flags.isNotEmpty) buf.write(' [${flags.join(',')}]');

      if (e.className == 'WebView' || e.className.contains('WebView')) {
        buf.write(' [WebView]');
      }

      buf.writeln();
      idx++;
    }

    for (final v in virtuals) {
      final display = v.text.length > 50 ? '${v.text.substring(0, 50)}...' : v.text;
      buf.writeln('#$idx [OCR] "$display" @(${v.cx},${v.cy})');
      idx++;
    }

    if (enriched.isEmpty && virtuals.isEmpty) {
      buf.writeln('(屏幕为空或无可交互元素)');
    }

    return buf.toString();
  }
}

class _EnrichedElement {
  final UIElement element;
  final List<String> ocrTexts;
  const _EnrichedElement({required this.element, required this.ocrTexts});
}

class _VirtualElement {
  final String text;
  final int cx, cy, left, top, right, bottom;
  const _VirtualElement({
    required this.text,
    required this.cx,
    required this.cy,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });
}
