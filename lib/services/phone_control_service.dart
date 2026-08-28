import 'native_bridge.dart';
import 'root_service.dart';
import 'shizuku_service.dart';

class PhoneControlService {
  static bool _available = false;
  static bool _checked = false;
  static String _executionMode = 'both';

  static bool get isAvailable => _available;
  static String get executionMode => _executionMode;

  static void setExecutionMode(String mode) {
    _executionMode = mode;
  }

  static Future<void> checkAvailability() async {
    if (_checked) return;
    _checked = true;
    try {
      final results = await Future.wait([
        RootService.isRootAvailable(),
        NativeBridge.isAccessibilityEnabled(),
        ShizukuService.checkAvailable(),
      ]);
      _available = (results[0] as bool) || (results[1] as bool) || (results[2] as bool);
      // Don't override execution mode — user chooses in settings
    } catch (_) {
      _available = false;
    }
  }

  /// Force re-check on next call (e.g. after granting permissions)
  static void resetAvailability() {
    _checked = false;
  }

  static Future<bool> openAccessibilitySettings() async {
    return await NativeBridge.openAccessibilitySettings();
  }

  static Future<bool> isA11yEnabled() async {
    return await NativeBridge.isAccessibilityEnabled();
  }

  // ── Action methods with mode support ──

  static Future<void> pressHome() async {
    if (_executionMode == 'shizuku') {
      await ShizukuService.pressHome();
      return;
    }
    if (_executionMode == 'a11y') {
      await NativeBridge.performAccessibilityAction('home', {});
      return;
    }
    try {
      await RootService.pressHome();
    } catch (_) {
      if (_executionMode == 'both') {
        await NativeBridge.performAccessibilityAction('home', {});
      }
    }
  }

  static Future<void> pressBack() async {
    if (_executionMode == 'shizuku') {
      await ShizukuService.pressBack();
      return;
    }
    if (_executionMode == 'a11y') {
      await NativeBridge.performAccessibilityAction('back', {});
      return;
    }
    try {
      await RootService.pressBack();
    } catch (_) {
      if (_executionMode == 'both') {
        await NativeBridge.performAccessibilityAction('back', {});
      }
    }
  }

  static Future<void> pressRecents() async {
    if (_executionMode == 'shizuku') {
      await ShizukuService.pressRecents();
      return;
    }
    if (_executionMode == 'a11y') {
      await NativeBridge.performAccessibilityAction('recents', {});
      return;
    }
    try {
      await RootService.pressRecents();
    } catch (_) {
      if (_executionMode == 'both') {
        await NativeBridge.performAccessibilityAction('recents', {});
      }
    }
  }

  static Future<void> tap(int x, int y) async {
    if (_executionMode == 'shizuku') {
      await ShizukuService.tap(x, y);
      return;
    }
    if (_executionMode == 'a11y') {
      await NativeBridge.performAccessibilityAction('tap', {'x': x.toDouble(), 'y': y.toDouble()});
      return;
    }
    try {
      await RootService.tap(x, y);
    } catch (_) {
      if (_executionMode == 'both') {
        await NativeBridge.performAccessibilityAction('tap', {'x': x.toDouble(), 'y': y.toDouble()});
      }
    }
  }

  static Future<void> swipe(int x1, int y1, int x2, int y2, int durationMs) async {
    if (_executionMode == 'shizuku') {
      await ShizukuService.swipe(x1, y1, x2, y2, durationMs);
      return;
    }
    if (_executionMode == 'a11y') {
      await NativeBridge.performAccessibilityAction('swipe', {
        'x1': x1.toDouble(), 'y1': y1.toDouble(),
        'x2': x2.toDouble(), 'y2': y2.toDouble(),
        'durationMs': durationMs,
      });
      return;
    }
    try {
      await RootService.swipe(x1, y1, x2, y2, durationMs);
    } catch (_) {
      if (_executionMode == 'both') {
        await NativeBridge.performAccessibilityAction('swipe', {
          'x1': x1.toDouble(), 'y1': y1.toDouble(),
          'x2': x2.toDouble(), 'y2': y2.toDouble(),
          'durationMs': durationMs,
        });
      }
    }
  }

  static Future<void> inputText(String text) async {
    if (_executionMode == 'shizuku') {
      await ShizukuService.inputText(text);
      return;
    }
    if (_executionMode == 'a11y') {
      await NativeBridge.performAccessibilityAction('inputText', {'text': text});
      return;
    }
    try {
      await RootService.inputText(text);
    } catch (_) {
      if (_executionMode == 'both') {
        await NativeBridge.performAccessibilityAction('inputText', {'text': text});
      }
    }
  }

  // ── Root/Shizuku operations (no a11y fallback) ──

  static Future<String> captureScreenshot() async {
    if (_executionMode == 'shizuku') return await ShizukuService.captureScreenshot();
    if (_executionMode == 'a11y') throw Exception('无障碍模式下不支持截图，请切换到 Shizuku 或 Root 模式');
    return await RootService.captureScreenshot();
  }

  static Future<String> captureScreenshotBase64() async {
    if (_executionMode == 'shizuku') return await ShizukuService.captureScreenshotBase64();
    if (_executionMode == 'a11y') throw Exception('无障碍模式下不支持截图');
    return await RootService.captureScreenshotBase64();
  }

  static Future<String> captureScreenshotJpeg() async {
    if (_executionMode == 'shizuku') return await ShizukuService.captureScreenshotJpeg();
    if (_executionMode == 'a11y') throw Exception('无障碍模式下不支持截图');
    return await RootService.captureScreenshotJpeg();
  }

  static Future<String> dumpUI() async {
    if (_executionMode == 'shizuku') return await ShizukuService.dumpUI();
    if (_executionMode == 'a11y') throw Exception('无障碍模式下不支持 UI 分析，请切换到 Shizuku 或 Root 模式');
    return await RootService.dumpUI();
  }

  static Future<String> getDisplaySize() async {
    if (_executionMode == 'shizuku') return await ShizukuService.getDisplaySize();
    if (_executionMode == 'a11y') return await RootService.getDisplaySize();
    return await RootService.getDisplaySize();
  }

  static Future<void> openApp(String pkg) async {
    if (_executionMode == 'shizuku') { await ShizukuService.openApp(pkg); return; }
    if (_executionMode == 'a11y') { await NativeBridge.performAccessibilityAction('openApp', {'package': pkg}); return; }
    await RootService.openApp(pkg);
  }

  static Future<List<Map<String, String>>> listInstalledApps() async {
    if (_executionMode == 'shizuku') return await ShizukuService.listInstalledApps();
    if (_executionMode == 'a11y') throw Exception('无障碍模式下不支持列出应用');
    return await RootService.listInstalledApps();
  }

  static Future<String?> findPackage(String query) async {
    if (_executionMode == 'shizuku') return await ShizukuService.findPackage(query);
    if (_executionMode == 'a11y') throw Exception('无障碍模式下不支持搜索应用');
    return await RootService.findPackage(query);
  }

  // ── Shell command extensions (root only) ──

  static Future<String> shellExec(String command) async {
    return await RootService.shellExec(command);
  }

  static Future<String> getSetting(String namespace, String key) async {
    return await RootService.getSetting(namespace, key);
  }

  static Future<void> putSetting(String namespace, String key, String value) async {
    await RootService.putSetting(namespace, key, value);
  }

  static Future<String> sendBroadcast(String action, [String extras = '']) async {
    return await RootService.sendBroadcast(action, extras);
  }

  static Future<String> getProp(String key) async {
    return await RootService.getProp(key);
  }

  static Future<void> forceStop(String packageName) async {
    await RootService.forceStop(packageName);
  }

  static Future<bool> clearData(String packageName) async {
    return await RootService.clearData(packageName);
  }

  static Future<void> grantPermission(String packageName, String permission) async {
    await RootService.grantPermission(packageName, permission);
  }

  static Future<void> revokePermission(String packageName, String permission) async {
    await RootService.revokePermission(packageName, permission);
  }

  static Future<String> getContent(String uri) async {
    return await RootService.getContent(uri);
  }

  static Future<bool> installApk(String path) async {
    return await RootService.installApk(path);
  }

  static Future<void> setWmDensity(int density) async {
    await RootService.setWmDensity(density);
  }

  static Future<void> setWmSize(String size) async {
    await RootService.setWmSize(size);
  }

  static Future<void> startService(String component) async {
    await RootService.startService(component);
  }

  // ── Accessibility node operations ──

  static Future<bool> clickNode(String label) async {
    final result = await NativeBridge.performAccessibilityAction('clickNode', {'text': label});
    return result == true;
  }

  static Future<bool> longClickNode(String label) async {
    final result = await NativeBridge.performAccessibilityAction('longClickNode', {'text': label});
    return result == true;
  }

  static Future<bool> scrollForward() async {
    final result = await NativeBridge.performAccessibilityAction('scrollForward', {});
    return result == true;
  }

  static Future<bool> scrollBackward() async {
    final result = await NativeBridge.performAccessibilityAction('scrollBackward', {});
    return result == true;
  }

  static Future<bool> appendText(String text) async {
    final result = await NativeBridge.performAccessibilityAction('appendText', {'text': text});
    return result == true;
  }

  static Future<bool> setNodeText(String text, String resourceId) async {
    final result = await NativeBridge.performAccessibilityAction('setNodeText', {'text': text, 'resourceId': resourceId});
    return result == true;
  }

  static Future<String> getNodeInfo() async {
    final result = await NativeBridge.performAccessibilityAction('getNodeInfo', {});
    return result is String ? result : '[]';
  }
}
