import 'package:flutter/services.dart';
import '../constants.dart';

class NativeBridge {
  static const _channel = MethodChannel(AppConstants.channelName);

  // ── Overlay action callback (Kotlin → Dart) ──
  static void Function(String action, String? text)? _onOverlayAction;
  static bool _listenerInitialized = false;

  static void setOverlayActionCallback(void Function(String action, String? text) callback) {
    _onOverlayAction = callback;
    _ensureListener();
  }

  static void _ensureListener() {
    if (_listenerInitialized) return;
    _listenerInitialized = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'agentOverlayAction') {
        final args = call.arguments as Map?;
        final action = args?['action'] as String? ?? '';
        final text = args?['text'] as String?;
        _onOverlayAction?.call(action, text);
      }
    });
  }

  static Future<String> getArch() async {
    return await _channel.invokeMethod('getArch');
  }

  static Future<String> getFilesDir() async {
    return await _channel.invokeMethod('getFilesDir');
  }

  static Future<String> getNativeLibDir() async {
    return await _channel.invokeMethod('getNativeLibDir');
  }

  static Future<String> getExternalStoragePath() async {
    return await _channel.invokeMethod('getExternalStoragePath');
  }

  static Future<bool> requestBatteryOptimization() async {
    return await _channel.invokeMethod('requestBatteryOptimization');
  }

  static Future<bool> isBatteryOptimized() async {
    return await _channel.invokeMethod('isBatteryOptimized');
  }

  static Future<bool> requestStoragePermission() async {
    return await _channel.invokeMethod('requestStoragePermission');
  }

  static Future<bool> hasStoragePermission() async {
    return await _channel.invokeMethod('hasStoragePermission');
  }

  static Future<bool> bringToForeground() async {
    return await _channel.invokeMethod('bringToForeground');
  }

  // Root
  static Future<bool> checkRootAccess() async {
    return await _channel.invokeMethod('checkRootAccess');
  }

  static Future<String> executeRootCommand(String command) async {
    final result = await _channel.invokeMethod('executeRootCommand', {'command': command});
    return result?.toString() ?? '';
  }

  static Future<String> captureScreenshot() async {
    final result = await _channel.invokeMethod('captureScreenshot');
    return result?.toString() ?? '';
  }

  static Future<String> captureScreenshotBase64() async {
    final result = await _channel.invokeMethod('captureScreenshotBase64');
    return result?.toString() ?? '';
  }

  static Future<String> captureScreenshotJpeg() async {
    final result = await _channel.invokeMethod('captureScreenshotJpeg');
    return result?.toString() ?? '';
  }

  // ── TTS ──

  static Future<void> initTts() async {
    await _channel.invokeMethod('initTts');
  }

  static Future<void> speakTts(String text, double speed) async {
    await _channel.invokeMethod('speakTts', {'text': text, 'speed': speed});
  }

  static Future<void> stopTts() async {
    await _channel.invokeMethod('stopTts');
  }

  // ── Voice Input ──

  static Future<String> startVoiceInput() async {
    try {
      final result = await _channel.invokeMethod('startVoiceInput');
      return result?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> stopVoiceInput() async {
    await _channel.invokeMethod('stopVoiceInput');
  }

  static Future<void> playAudio(String filePath) async {
    await _channel.invokeMethod('playAudio', {'path': filePath});
  }

  static Future<void> stopAudio() async {
    await _channel.invokeMethod('stopAudio');
  }

  static Future<bool> openHtmlFile(String filePath) async {
    try {
      final result = await _channel.invokeMethod('openHtmlFile', {'path': filePath});
      return result == true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, String>> getDeviceInfo() async {
    final result = await _channel.invokeMethod('getDeviceInfo');
    final map = <String, String>{};
    if (result is Map) {
      result.forEach((k, v) => map[k.toString()] = v.toString());
    }
    return map;
  }

  static Future<bool> isAccessibilityEnabled() async {
    final result = await _channel.invokeMethod('isAccessibilityEnabled');
    return result == true;
  }

  static Future<bool> openAccessibilitySettings() async {
    final result = await _channel.invokeMethod('openAccessibilitySettings');
    return result == true;
  }

  static Future<bool> showAgentOverlay(String status, int step) async {
    final result = await _channel.invokeMethod('showAgentOverlay', {'status': status, 'step': step});
    return result == true;
  }

  static Future<bool> updateAgentOverlay(String status, int step, {bool paused = false}) async {
    _ensureListener();
    final result = await _channel.invokeMethod('updateAgentOverlay', {
      'status': status,
      'step': step,
      'paused': paused,
    });
    return result == true;
  }

  static Future<bool> hideAgentOverlay() async {
    final result = await _channel.invokeMethod('hideAgentOverlay');
    return result == true;
  }

  static Future<bool> showAgentInput(String hint) async {
    final result = await _channel.invokeMethod('showAgentInput', {'hint': hint});
    return result == true;
  }

  static Future<bool> hideAgentInput() async {
    final result = await _channel.invokeMethod('hideAgentInput');
    return result == true;
  }

  static Future<bool> hasOverlayPermission() async {
    final result = await _channel.invokeMethod('hasOverlayPermission');
    return result == true;
  }

  static Future<bool> requestOverlayPermission() async {
    final result = await _channel.invokeMethod('requestOverlayPermission');
    return result == true;
  }

  static Future<dynamic> performAccessibilityAction(String action, Map<String, dynamic> params) async {
    final result = await _channel.invokeMethod('performAccessibilityAction', {
      'action': action,
      'params': params,
    });
    return result;
  }

  // ── Shizuku ──

  static Future<Map<String, dynamic>> checkShizukuAccess() async {
    try {
      final result = await _channel.invokeMethod('checkShizukuAccess');
      if (result is Map) {
        return result.map((k, v) => MapEntry(k.toString(), v));
      }
      return {'available': false};
    } catch (_) {
      return {'available': false};
    }
  }

  static Future<bool> requestShizukuPermission() async {
    try {
      return await _channel.invokeMethod('requestShizukuPermission') == true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> executeShizukuCommand(String command) async {
    try {
      final result = await _channel.invokeMethod('executeShizukuCommand', {'command': command});
      if (result is Map) {
        return result.map((k, v) => MapEntry(k.toString(), v));
      }
      return {'output': '', 'error': 'unexpected result', 'exitCode': -1};
    } catch (e) {
      return {'output': '', 'error': e.toString(), 'exitCode': -1};
    }
  }

  // ── File System Access (root) ──

  static Future<String> listDirectory(String path) async {
    try {
      final result = await _channel.invokeMethod('listDirectory', {'path': path});
      return result?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> readFile(String path, {int maxBytes = 65536}) async {
    try {
      final result = await _channel.invokeMethod('readFile', {'path': path, 'maxBytes': maxBytes});
      return result?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> searchFiles(String rootPath, String pattern) async {
    try {
      final result = await _channel.invokeMethod('searchFiles', {'rootPath': rootPath, 'pattern': pattern});
      return result?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> statFile(String path) async {
    try {
      final result = await _channel.invokeMethod('statFile', {'path': path});
      return result?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  // ── Browser Automation ──

  static Future<bool> browserOpen(String url) async {
    try {
      final result = await _channel.invokeMethod('browserOpen', {'url': url});
      return result == true;
    } catch (_) {
      return false;
    }
  }

  static Future<String> browserGetStructure() async {
    try {
      final result = await _channel.invokeMethod('browserGetStructure');
      return result?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<bool> browserClick(int index) async {
    try {
      final result = await _channel.invokeMethod('browserClick', {'index': index});
      return result == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> browserInput(int index, String text) async {
    try {
      final result = await _channel.invokeMethod('browserInput', {'index': index, 'text': text});
      return result == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> browserScroll(String direction) async {
    try {
      final result = await _channel.invokeMethod('browserScroll', {'direction': direction});
      return result == true;
    } catch (_) {
      return false;
    }
  }
}
