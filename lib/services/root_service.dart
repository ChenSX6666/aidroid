import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'native_bridge.dart';
import 'log_service.dart';

class RootService {
  static bool _hasRoot = false;
  static bool _rootChecked = false;

  static List<Map<String, String>>? _cachedApps;
  static Map<String, String>? _persistedAppMap; // label→package, persisted

  static const _appMapPrefKey = 'persisted_app_label_map';

  /// Clear cache to force re-fetch on next call
  static void clearAppCache() {
    _cachedApps = null;
    _persistedAppMap = null;
    SharedPreferences.getInstance().then((p) => p.remove(_appMapPrefKey));
  }

  /// Load persisted app map from SharedPreferences
  static Future<void> loadPersistedApps() async {
    if (_persistedAppMap != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_appMapPrefKey);
      if (json != null) {
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        _persistedAppMap = decoded.map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (_) {}
    _persistedAppMap ??= {};
  }

  /// Persist app map to SharedPreferences
  static Future<void> _persistAppMap(Map<String, String> map) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_appMapPrefKey, jsonEncode(map));
      _persistedAppMap = map;
    } catch (e) {
      LogService.error('persistAppMap error: $e');
    }
  }

  static Future<bool> isRootAvailable() async {
    try {
      final result = await NativeBridge.checkRootAccess();
      _hasRoot = result;
      _rootChecked = true;
      return _hasRoot;
    } catch (_) {
      _hasRoot = false;
      _rootChecked = true;
      return false;
    }
  }

  static bool get hasRoot => _hasRoot;
  static bool get rootChecked => _rootChecked;

  static Future<void> tap(int x, int y) async {
    await NativeBridge.executeRootCommand('input tap $x $y');
  }

  static Future<void> swipe(int x1, int y1, int x2, int y2, int durationMs) async {
    await NativeBridge.executeRootCommand('input swipe $x1 $y1 $x2 $y2 $durationMs');
  }

  static Future<void> inputText(String text) async {
    final escaped = text.replaceAll("'", "'\\''");
    await NativeBridge.executeRootCommand("input text '$escaped'");
  }

  static Future<void> keyEvent(int keyCode) async {
    await NativeBridge.executeRootCommand('input keyevent $keyCode');
  }

  static Future<void> pressHome() async {
    await keyEvent(3);
  }

  static Future<void> pressBack() async {
    await keyEvent(4);
  }

  static Future<void> pressRecents() async {
    await keyEvent(187);
  }

  static Future<String> captureScreenshot() async {
    return await NativeBridge.captureScreenshot();
  }

  static Future<String> captureScreenshotBase64() async {
    return await NativeBridge.captureScreenshotBase64();
  }

  static Future<String> captureScreenshotJpeg() async {
    return await NativeBridge.captureScreenshotJpeg();
  }

  static Future<String> getDisplaySize() async {
    return await NativeBridge.executeRootCommand('wm size');
  }

  static Future<String> dumpUI() async {
    return await NativeBridge.executeRootCommand(
      'uiautomator dump /data/local/tmp/ui.xml && cat /data/local/tmp/ui.xml',
    );
  }

  static Future<void> openApp(String packageName) async {
    LogService.command('openApp: $packageName');
    final result = await NativeBridge.executeRootCommand(
      'am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER $packageName 2>/dev/null',
    );
    LogService.info('openApp result: ${result.length > 100 ? result.substring(0, 100) : result}');
  }

  /// Returns list of installed apps as [{package, label}]
  /// Scans third-party apps, gets real labels, persists to SharedPreferences.
  /// Cached after first call. Use clearAppCache() to force refresh.
  static Future<List<Map<String, String>>> listInstalledApps() async {
    if (_cachedApps != null) return _cachedApps!;

    // Get third-party apps
    final result = await NativeBridge.executeRootCommand(
      'pm list packages -3 2>/dev/null',
    );
    final packages = <String>[];
    for (final line in result.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('package:')) continue;
      final pkg = trimmed.substring(8).trim();
      if (pkg.isNotEmpty) packages.add(pkg);
    }

    // Get real labels via dumpsys per-package (batched in one shell command)
    final sb = StringBuffer();
    for (final pkg in packages) {
      sb.writeln('dumpsys package "$pkg" 2>/dev/null | grep -m1 "ApplicationLabel" || echo "LABEL:${pkg.split('.').last}"');
    }
    final labelResult = await NativeBridge.executeRootCommand(sb.toString());

    final apps = <Map<String, String>>[];
    final labelMap = <String, String>{}; // label→package for persistence
    int idx = 0;
    for (final line in labelResult.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('ApplicationLabel=')) {
        final label = trimmed.substring('ApplicationLabel='.length).trim();
        if (idx < packages.length) {
          final l = label.isNotEmpty ? label : packages[idx].split('.').last;
          apps.add({'package': packages[idx], 'label': l});
          labelMap[l.toLowerCase()] = packages[idx];
          idx++;
        }
      } else if (trimmed.startsWith('LABEL:')) {
        if (idx < packages.length) {
          final label = trimmed.substring(6).trim();
          apps.add({'package': packages[idx], 'label': label});
          labelMap[label.toLowerCase()] = packages[idx];
          idx++;
        }
      }
    }
    // Fill remaining
    while (idx < packages.length) {
      final parts = packages[idx].split('.');
      final label = parts.isNotEmpty ? parts.last : packages[idx];
      apps.add({'package': packages[idx], 'label': label});
      labelMap[label.toLowerCase()] = packages[idx];
      idx++;
    }

    _cachedApps = apps;
    await _persistAppMap(labelMap);
    return apps;
  }

  /// Fuzzy match app name to package. Returns null if no match.
  // ── Shell command extensions ──

  /// Execute arbitrary shell command as root
  static Future<String> shellExec(String command) async {
    final result = await NativeBridge.executeRootCommand(command);
    return result;
  }

  /// Read system setting: settings get <namespace> <key>
  static Future<String> getSetting(String namespace, String key) async {
    return await NativeBridge.executeRootCommand('settings get $namespace $key');
  }

  /// Write system setting: settings put <namespace> <key> <value>
  static Future<void> putSetting(String namespace, String key, String value) async {
    await NativeBridge.executeRootCommand('settings put $namespace $key $value');
  }

  /// Send broadcast: am broadcast -a <action> [extras]
  static Future<String> sendBroadcast(String action, [String extras = '']) async {
    return await NativeBridge.executeRootCommand('am broadcast -a $action $extras');
  }

  /// Read system property
  static Future<String> getProp(String key) async {
    return await NativeBridge.executeRootCommand('getprop $key');
  }

  /// Force stop an app
  static Future<void> forceStop(String packageName) async {
    await NativeBridge.executeRootCommand('am force-stop $packageName');
  }

  /// Clear app data
  static Future<bool> clearData(String packageName) async {
    final result = await NativeBridge.executeRootCommand('pm clear $packageName');
    return result.contains('Success');
  }

  /// Grant permission to app
  static Future<void> grantPermission(String packageName, String permission) async {
    await NativeBridge.executeRootCommand('pm grant $packageName $permission');
  }

  /// Revoke permission from app
  static Future<void> revokePermission(String packageName, String permission) async {
    await NativeBridge.executeRootCommand('pm revoke $packageName $permission');
  }

  /// Query ContentProvider
  static Future<String> getContent(String uri) async {
    return await NativeBridge.executeRootCommand('content query --uri $uri');
  }

  /// Install APK
  static Future<bool> installApk(String path) async {
    final result = await NativeBridge.executeRootCommand('pm install -r $path');
    return result.contains('Success');
  }

  /// Set screen density
  static Future<void> setWmDensity(int density) async {
    await NativeBridge.executeRootCommand('wm density $density');
  }

  /// Set screen size
  static Future<void> setWmSize(String size) async {
    await NativeBridge.executeRootCommand('wm size $size');
  }

  /// Start a service
  static Future<void> startService(String component) async {
    await NativeBridge.executeRootCommand('am startservice $component');
  }

  static Future<String?> findPackage(String query) async {
    final lower = query.toLowerCase();

    // 1. Check persisted app map (label→package, auto-scanned)
    await loadPersistedApps();
    if (_persistedAppMap != null) {
      // Exact match
      if (_persistedAppMap!.containsKey(lower)) return _persistedAppMap![lower];
      // Fuzzy match
      for (final entry in _persistedAppMap!.entries) {
        if (entry.key.contains(lower) || lower.contains(entry.key)) {
          return entry.value;
        }
      }
    }

    // 2. Check in-memory cached apps
    if (_cachedApps != null) {
      for (final app in _cachedApps!) {
        final pkg = app['package'] ?? '';
        final label = app['label'] ?? '';
        if (pkg.toLowerCase().contains(lower) || label.toLowerCase().contains(lower)) {
          return pkg;
        }
      }
    }

    // 3. Shell fallback: grep all packages
    try {
      final result = await NativeBridge.executeRootCommand(
        "pm list packages 2>/dev/null | grep -i '$query' | head -5",
      );
      final trimmed = result.trim();
      if (trimmed.startsWith('package:')) return trimmed.substring(8);
    } catch (_) {}

    return null;
  }
}
