import 'dart:io';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'log_service.dart';

class ImageLabelService {
  static ImageLabeler? __labeler;
  static ImageLabeler? get _labeler {
    if (__labeler != null) return __labeler;
    try {
      __labeler = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.5));
      return __labeler;
    } catch (_) {
      return null;
    }
  }

  static bool get isAvailable {
    _labeler; // trigger init
    return __labeler != null;
  }

  /// Label a screenshot file. Returns list of labels with confidence.
  static Future<List<({String label, double confidence})>> labelFile(String filePath) async {
    try {
      final labeler = _labeler;
      if (labeler == null) return [];

      final file = File(filePath);
      if (!await file.exists()) return [];

      final inputImage = InputImage.fromFilePath(filePath);
      final labels = await labeler.processImage(inputImage);

      return labels
          .map((l) => (label: _translate(l.label), confidence: l.confidence))
          .toList();
    } catch (e) {
      LogService.error('Image Labeling 失败: $e');
      return [];
    }
  }

  /// Check if labels suggest interactive UI elements exist
  static bool hasInteractiveElements(List<({String label, double confidence})> labels) {
    final interactiveKeys = ['按钮', '菜单', '图标', '用户界面', '文字', '输入框', '弹窗'];
    return labels.any((l) => interactiveKeys.any((k) => l.label.contains(k)));
  }

  /// Build a human-readable visual summary from labels
  static String describe(List<({String label, double confidence})> labels) {
    if (labels.isEmpty) return '';

    final top = labels.take(5).map((l) => l.label).toList();
    final significant = top.where((t) => t != '文字' && t != '字体').toList();

    if (significant.isEmpty && top.isNotEmpty) {
      return '画面类型: ${top.join(", ")}';
    }

    final parts = <String>[];
    if (significant.isNotEmpty) parts.add('画面类型: ${significant.join(", ")}');

    final hasButtons = labels.any((l) => l.label == '按钮');
    final hasMenu = labels.any((l) => l.label == '菜单');
    final hasUI = labels.any((l) => l.label == '用户界面');
    final hasText = labels.any((l) => l.label == '文字');

    if (hasButtons) parts.add('包含按钮');
    if (hasMenu) parts.add('包含菜单');
    if (hasUI) parts.add('包含用户界面元素');
    if (hasText) parts.add('包含文字内容');

    return parts.join('; ');
  }

  /// Translate English labels to Chinese
  static String _translate(String label) {
    switch (label.toLowerCase()) {
      case 'game': return '游戏画面';
      case 'user interface': case 'ui': return '用户界面';
      case 'button': return '按钮';
      case 'text': return '文字';
      case 'menu': return '菜单';
      case 'icon': return '图标';
      case 'font': return '字体';
      case 'screenshot': return '截图';
      case 'web page': case 'website': return '网页';
      case 'mobile app': return '手机应用';
      case 'dialog': case 'popup': return '弹窗';
      case 'navigation bar': return '导航栏';
      case 'toolbar': return '工具栏';
      case 'list': return '列表';
      case 'grid': return '网格';
      case 'input field': case 'text box': return '输入框';
      case 'logo': return '标志';
      case 'banner': return '横幅';
      case 'card': return '卡片';
      default: return label;
    }
  }

  static Future<void> dispose() async {
    await __labeler?.close();
    __labeler = null;
  }
}
