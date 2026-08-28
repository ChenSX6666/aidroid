import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'native_bridge.dart';
import 'root_service.dart';
import 'log_service.dart';

class DeviceScanService {
  static Map<String, dynamic>? _cachedResult;
  static DateTime? _cacheTime;
  static bool _initialized = false;

  static const _cacheDuration = Duration(hours: 24);
  static const _prefKey = 'device_scan_cache';
  static const _prefTimeKey = 'device_scan_time';

  static bool get hasCachedResult =>
      _cachedResult != null &&
      _cacheTime != null &&
      DateTime.now().difference(_cacheTime!) < _cacheDuration;

  /// 是否有永久存储的扫描结果（即使过期也可用）
  static bool get hasPersistedResult => _cachedResult != null;

  static Map<String, dynamic>? get cachedResult => _cachedResult;

  /// 初始化：从 SharedPreferences 加载上次扫描结果
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKey);
      final timeStr = prefs.getString(_prefTimeKey);
      if (json != null && json.isNotEmpty) {
        _cachedResult = jsonDecode(json) as Map<String, dynamic>;
        if (timeStr != null) {
          _cacheTime = DateTime.tryParse(timeStr);
        }
      }
    } catch (e) {
      LogService.error('DeviceScanService init error: $e');
    }
  }

  static void clearCache() {
    _cachedResult = null;
    _cacheTime = null;
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove(_prefKey);
      prefs.remove(_prefTimeKey);
    });
  }

  /// 持久化扫描结果到 SharedPreferences
  static Future<void> _persist(Map<String, dynamic> result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(result));
      await prefs.setString(_prefTimeKey, DateTime.now().toIso8601String());
    } catch (e) {
      LogService.error('DeviceScanService persist error: $e');
    }
  }

  static Future<Map<String, dynamic>> scanDevice() async {
    if (hasCachedResult) return _cachedResult!;

    final result = <String, dynamic>{};

    try {
      final futures = <Future<void>>[
        _scanBasicInfo(result),
        _scanStorage(result),
        _scanBattery(result),
        _scanApps(result),
        _scanNetwork(result),
        _scanDisplay(result),
      ];
      await Future.wait(futures, eagerError: true);
    } catch (e) {
      LogService.error('Device scan error: $e');
    }

    _cachedResult = result;
    _cacheTime = DateTime.now();
    await _persist(result);
    return result;
  }

  static Future<void> _scanBasicInfo(Map<String, dynamic> result) async {
    try {
      final deviceInfo = await NativeBridge.getDeviceInfo();
      result['model'] = deviceInfo['model'] ?? '未知';
      result['brand'] = deviceInfo['brand'] ?? '未知';
      result['androidVersion'] = deviceInfo['version'] ?? '未知';
      result['sdkInt'] = deviceInfo['sdkInt'] ?? '未知';
    } catch (_) {}

    try {
      final arch = await NativeBridge.getArch();
      result['arch'] = arch;
    } catch (_) {}

    try {
      final rootInfo = await RootService.isRootAvailable();
      result['rooted'] = rootInfo;
    } catch (_) {
      result['rooted'] = false;
    }

    try {
      final cpuInfo = await RootService.shellExec('cat /proc/cpuinfo | head -10');
      result['cpuInfo'] = cpuInfo.trim();
    } catch (_) {}
  }

  static Future<void> _scanStorage(Map<String, dynamic> result) async {
    try {
      final df = await RootService.shellExec('df -h /data 2>/dev/null');
      final lines = df.split('\n');
      if (lines.length >= 2) {
        final parts = lines[1].split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          result['storageTotal'] = parts[1];
          result['storageUsed'] = parts[2];
          result['storageAvail'] = parts[3];
        }
      }
    } catch (_) {}

    try {
      final mem = await RootService.shellExec('cat /proc/meminfo | head -3');
      final match = RegExp(r'MemTotal:\s+(\d+)').firstMatch(mem);
      if (match != null) {
        final kb = int.parse(match.group(1)!);
        result['ramTotalMB'] = (kb / 1024).round();
      }
      final match2 = RegExp(r'MemAvailable:\s+(\d+)').firstMatch(mem);
      if (match2 != null) {
        final kb = int.parse(match2.group(1)!);
        result['ramAvailMB'] = (kb / 1024).round();
      }
    } catch (_) {}
  }

  static Future<void> _scanBattery(Map<String, dynamic> result) async {
    try {
      final dump = await RootService.shellExec('dumpsys battery');
      final levelMatch = RegExp(r'level:\s*(\d+)').firstMatch(dump);
      if (levelMatch != null) result['batteryLevel'] = int.parse(levelMatch.group(1)!);
      final statusMatch = RegExp(r'status:\s*(\d+)').firstMatch(dump);
      if (statusMatch != null) {
        final s = int.parse(statusMatch.group(1)!);
        result['batteryStatus'] = s == 2 ? '充电中' : s == 5 ? '满电' : '未充电';
      }
      final tempMatch = RegExp(r'temperature:\s*(\d+)').firstMatch(dump);
      if (tempMatch != null) result['batteryTemp'] = '${(int.parse(tempMatch.group(1)!) / 10).toStringAsFixed(1)}°C';
    } catch (_) {}
  }

  static Future<void> _scanApps(Map<String, dynamic> result) async {
    try {
      final apps = await RootService.listInstalledApps();
      result['appCount'] = apps.length;
      // 存完整映射：应用名 → 包名
      final appMap = <String, String>{};
      for (final a in apps) {
        final label = a['label'] ?? '';
        final pkg = a['package'] ?? '';
        if (label.isNotEmpty && pkg.isNotEmpty) {
          appMap[label] = pkg;
        }
      }
      result['apps'] = appMap;
    } catch (_) {}
  }

  static Future<void> _scanNetwork(Map<String, dynamic> result) async {
    try {
      final wifi = await RootService.shellExec('dumpsys wifi | grep "mWifiInfo" | head -1');
      final ssidMatch = RegExp(r'SSID:\s*"?([^",]+)').firstMatch(wifi);
      if (ssidMatch != null) result['wifiSSID'] = ssidMatch.group(1);
    } catch (_) {}

    try {
      final ip = await RootService.shellExec('ip route get 1.1.1.1 2>/dev/null | head -1');
      final srcMatch = RegExp(r'src\s+(\S+)').firstMatch(ip);
      if (srcMatch != null) result['ipAddress'] = srcMatch.group(1);
    } catch (_) {}
  }

  static Future<void> _scanDisplay(Map<String, dynamic> result) async {
    try {
      final size = await NativeBridge.executeRootCommand('wm size');
      result['screenSize'] = size.trim();
    } catch (_) {}

    try {
      final density = await NativeBridge.executeRootCommand('wm density');
      result['density'] = density.trim();
    } catch (_) {}
  }

  static String formatScanResult(Map<String, dynamic> data) {
    final buf = StringBuffer();

    buf.writeln('=== 设备信息 ===');
    buf.writeln('型号: ${data['brand'] ?? '?'} ${data['model'] ?? '?'}');
    buf.writeln('Android: ${data['androidVersion'] ?? '?'} (SDK ${data['sdkInt'] ?? '?'})');
    buf.writeln('架构: ${data['arch'] ?? '?'}');
    buf.writeln('Root: ${data['rooted'] == true ? '已获取' : '未获取'}');

    if (data['screenSize'] != null) buf.writeln('屏幕: ${data['screenSize']}');
    if (data['density'] != null) buf.writeln('DPI: ${data['density']}');

    buf.writeln('\n=== 存储 ===');
    if (data['storageTotal'] != null) {
      buf.writeln('总容量: ${data['storageTotal']}');
      buf.writeln('已用: ${data['storageUsed']}');
      buf.writeln('可用: ${data['storageAvail']}');
    }
    if (data['ramTotalMB'] != null) {
      buf.writeln('RAM: ${data['ramTotalMB']}MB (可用 ${data['ramAvailMB'] ?? '?'}MB)');
    }

    buf.writeln('\n=== 电池 ===');
    if (data['batteryLevel'] != null) buf.writeln('电量: ${data['batteryLevel']}%');
    if (data['batteryStatus'] != null) buf.writeln('状态: ${data['batteryStatus']}');
    if (data['batteryTemp'] != null) buf.writeln('温度: ${data['batteryTemp']}');

    buf.writeln('\n=== 网络 ===');
    if (data['wifiSSID'] != null) buf.writeln('WiFi: ${data['wifiSSID']}');
    if (data['ipAddress'] != null) buf.writeln('IP: ${data['ipAddress']}');

    buf.writeln('\n=== 应用 ===');
    if (data['appCount'] != null) buf.writeln('已安装: ${data['appCount']} 个');
    if (data['apps'] != null) {
      final apps = data['apps'] as Map<String, dynamic>;
      for (final entry in apps.entries) {
        buf.writeln('  ${entry.key}: ${entry.value}');
      }
    }

    return buf.toString();
  }
}
