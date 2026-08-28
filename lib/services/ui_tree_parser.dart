class UIElement {
  final int index;
  final String className;
  final String text;
  final String contentDesc;
  final String resourceId;
  final int cx, cy;
  final int left, top, right, bottom;
  final bool isClickable;
  final bool isLongClickable;
  final bool isScrollable;
  final bool isEditable;
  final bool isCheckable;
  final bool isChecked;
  final bool isEnabled;
  final bool isFocused;

  const UIElement({
    required this.index,
    required this.className,
    required this.text,
    required this.contentDesc,
    required this.resourceId,
    required this.cx,
    required this.cy,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.isClickable,
    required this.isLongClickable,
    required this.isScrollable,
    required this.isEditable,
    required this.isCheckable,
    required this.isChecked,
    required this.isEnabled,
    required this.isFocused,
  });

  String get label {
    if (text.isNotEmpty) return text;
    if (contentDesc.isNotEmpty) return contentDesc;
    final parts = resourceId.split('/');
    if (parts.length > 1) return parts.last.replaceAll('_', ' ');
    return '';
  }
}

class UITreeParser {
  static const _maxElements = 300;

  static String buildScreenDescription(String xml, String displaySize) {
    final elements = parse(xml);
    return formatForPrompt(elements, displaySize);
  }

  static List<UIElement> parse(String xml) {
    final elements = <UIElement>[];

    final nodeRegex = RegExp(r'<node\s+([^>]+?)(?:\s*/)?>');
    final attrRegex = RegExp(r'''(\S+)\s*=\s*"([^"]*)"''');

    for (final m in nodeRegex.allMatches(xml)) {
      final attrStr = m.group(1)!;
      final attrs = <String, String>{};
      for (final a in attrRegex.allMatches(attrStr)) {
        attrs[a.group(1)!] = a.group(2)!;
      }

      if (!_isInteractive(attrs)) continue;

      final bounds = _parseBounds(attrs['bounds'] ?? '');
      if (bounds == null) continue;

      final l = bounds[0];
      final t = bounds[1];
      final r = bounds[2];
      final b = bounds[3];

      if (r <= 0 || b <= 0) continue;

      final text = (attrs['text'] ?? '').replaceAll(RegExp(r'[\n\r\t]'), ' ').trim();
      final cd = (attrs['content-desc'] ?? '').replaceAll(RegExp(r'[\n\r\t]'), ' ').trim();
      final cls = _simplifyClass(attrs['class'] ?? '');

      elements.add(UIElement(
        index: elements.length,
        className: cls,
        text: text,
        contentDesc: cd,
        resourceId: attrs['resource-id'] ?? '',
        cx: (l + r) ~/ 2,
        cy: (t + b) ~/ 2,
        left: l, top: t, right: r, bottom: b,
        isClickable: attrs['clickable'] == 'true',
        isLongClickable: attrs['long-clickable'] == 'true',
        isScrollable: attrs['scrollable'] == 'true',
        isEditable: cls == 'EditText' || cls.contains('EditText'),
        isCheckable: attrs['checkable'] == 'true',
        isChecked: attrs['checked'] == 'true',
        isEnabled: attrs['enabled'] != 'false',
        isFocused: attrs['focused'] == 'true',
      ));

      if (elements.length >= _maxElements) break;
    }

    // Sort by importance so LLM sees most relevant elements first
    elements.sort((a, b) => _importanceScore(b).compareTo(_importanceScore(a)));
    for (int i = 0; i < elements.length; i++) {
      elements[i] = UIElement(
        index: i,
        className: elements[i].className,
        text: elements[i].text,
        contentDesc: elements[i].contentDesc,
        resourceId: elements[i].resourceId,
        cx: elements[i].cx,
        cy: elements[i].cy,
        left: elements[i].left,
        top: elements[i].top,
        right: elements[i].right,
        bottom: elements[i].bottom,
        isClickable: elements[i].isClickable,
        isLongClickable: elements[i].isLongClickable,
        isScrollable: elements[i].isScrollable,
        isEditable: elements[i].isEditable,
        isCheckable: elements[i].isCheckable,
        isChecked: elements[i].isChecked,
        isEnabled: elements[i].isEnabled,
        isFocused: elements[i].isFocused,
      );
    }

    return elements;
  }

  static int _importanceScore(UIElement e) {
    int score = 0;
    if (e.label.isNotEmpty) score += 100;
    if (e.isClickable) score += 50;
    if (e.isEditable) score += 40;
    if (e.isLongClickable) score += 20;
    if (e.isScrollable) score += 10;
    if (e.isCheckable) score += 10;
    if (e.isFocused) score += 5;
    final w = e.right - e.left;
    final h = e.bottom - e.top;
    if (w > 30 && w < 600 && h > 30 && h < 200) score += 5;
    return score;
  }

  static bool _isInteractive(Map<String, String> attrs) {
    if (attrs['enabled'] == 'false') return false;

    if (attrs['clickable'] == 'true') return true;
    if (attrs['long-clickable'] == 'true') return true;
    if (attrs['focusable'] == 'true') return true;
    if (attrs['scrollable'] == 'true') return true;
    if (attrs['checkable'] == 'true') return true;

    if ((attrs['text'] ?? '').trim().isNotEmpty) return true;
    if ((attrs['content-desc'] ?? '').trim().isNotEmpty) return true;

    final cls = attrs['class'] ?? '';
    if (cls.contains('EditText')) return true;

    return false;
  }

  static List<int>? _parseBounds(String bounds) {
    final m = RegExp(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]').firstMatch(bounds);
    if (m == null) return null;
    return [
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
    ];
  }

  static String _simplifyClass(String fullClass) {
    final parts = fullClass.split('.');
    return parts.last;
  }

  static String formatForPrompt(List<UIElement> elements, String displaySize) {
    final buf = StringBuffer();
    buf.writeln('屏幕: $displaySize');
    buf.writeln('交互元素: ${elements.length} 个');
    buf.writeln();

    for (final e in elements) {
      buf.write('#${e.index} ${e.className}');

      final label = e.label;
      if (label.isNotEmpty) {
        final display = label.length > 50 ? '${label.substring(0, 50)}...' : label;
        buf.write(' "$display"');
      }

      buf.write(' @(${e.cx},${e.cy})');

      if (e.resourceId.isNotEmpty) {
        buf.write(' id=${e.resourceId}');
      }

      final flags = <String>[];
      if (e.isClickable) flags.add('T');       // Tap
      if (e.isLongClickable) flags.add('L');   // Long-press
      if (e.isScrollable) flags.add('S');      // Scroll
      if (e.isEditable) flags.add('E');        // Edit
      if (e.isCheckable) flags.add(e.isChecked ? 'V' : 'C'); // Checked/Checkable
      if (e.isFocused) flags.add('F');         // Focused

      if (flags.isNotEmpty) {
        buf.write(' [${flags.join(',')}]');
      }

      if (e.className == 'WebView' || e.className.contains('WebView')) {
        buf.write(' [WebView]');
      }

      buf.writeln();
    }

    if (elements.length >= _maxElements) {
      buf.writeln('(已省略更多元素)');
    }

    if (elements.isEmpty) {
      buf.writeln('(屏幕为空或无可交互元素)');
    }

    return buf.toString();
  }
}
