import 'package:shared_preferences/shared_preferences.dart';

/// Three-tier tool permission: allow / ask / deny.
/// Default is "ask" for all risky tools.
class ToolPermissionService {
  static const _prefKey = 'tool_permissions';
  static const allow = 'allow';
  static const ask = 'ask';
  static const deny = 'deny';

  static const riskyTools = [
    'shell',
    'clear_data',
    'force_stop',
    'install_apk',
    'settings_put',
    'broadcast',
    'grant_permission',
    'revoke_permission',
  ];

  static Future<String> getPermission(String tool) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null) {
        final map = _decode(raw);
        return map[tool] ?? ask;
      }
    } catch (_) {}
    return ask;
  }

  static Future<Map<String, String>> getAllPermissions() async {
    final map = <String, String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null) {
        map.addAll(_decode(raw));
      }
    } catch (_) {}
    return map;
  }

  static Future<void> setPermission(String tool, String level) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      final map = raw != null ? _decode(raw) : <String, String>{};
      map[tool] = level;
      await prefs.setString(_prefKey, _encode(map));
    } catch (_) {}
  }

  static Map<String, String> _decode(String raw) {
    final map = <String, String>{};
    for (final line in raw.split('\n')) {
      final idx = line.indexOf('=');
      if (idx > 0) {
        map[line.substring(0, idx)] = line.substring(idx + 1);
      }
    }
    return map;
  }

  static String _encode(Map<String, String> map) {
    return map.entries.map((e) => '${e.key}=${e.value}').join('\n');
  }
}
