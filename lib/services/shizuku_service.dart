import 'native_bridge.dart';
import 'log_service.dart';

class ShizukuService {
  static bool _available = false;
  static bool _checked = false;

  static List<Map<String, String>>? _cachedApps;

  static bool get isAvailable => _available;
  static bool get checked => _checked;

  static void clearAppCache() {
    _cachedApps = null;
  }

  static Future<bool> checkAvailable() async {
    if (_checked) return _available;
    try {
      final result = await NativeBridge.checkShizukuAccess();
      _available = result['available'] == true;
      _checked = true;
      return _available;
    } catch (_) {
      _available = false;
      _checked = true;
      return false;
    }
  }

  static Future<bool> requestPermission() async {
    return await NativeBridge.requestShizukuPermission();
  }

  static Future<String> exec(String cmd) async {
    final result = await NativeBridge.executeShizukuCommand(cmd);
    if (result['exitCode'] != 0) {
      final err = result['error'] ?? '';
      throw Exception(err.isNotEmpty ? err : 'Shizuku command failed (exit ${result['exitCode']})');
    }
    return result['output'] ?? '';
  }

  static Future<void> tap(int x, int y) async {
    await exec('input tap $x $y');
  }

  static Future<void> swipe(int x1, int y1, int x2, int y2, int durationMs) async {
    await exec('input swipe $x1 $y1 $x2 $y2 $durationMs');
  }

  static Future<void> inputText(String text) async {
    final escaped = text.replaceAll("'", "'\\''");
    await exec("input text '$escaped'");
  }

  static Future<void> keyEvent(int keyCode) async {
    await exec('input keyevent $keyCode');
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
    final dir = await NativeBridge.getFilesDir();
    final path = '$dir/shizuku_screen.png';
    await exec('screencap -p $path');
    return path;
  }

  static Future<String> captureScreenshotBase64() async {
    final output = await exec('screencap -p /dev/stdout 2>/dev/null | base64 -w0');
    return output;
  }

  static Future<String> captureScreenshotJpeg() async {
    final dir = await NativeBridge.getFilesDir();
    final path = '$dir/shizuku_screen_jpg.png';
    await exec('screencap -p $path');
    return path;
  }

  static Future<String> getDisplaySize() async {
    return await exec('wm size');
  }

  static Future<String> dumpUI() async {
    return await exec('uiautomator dump /data/local/tmp/ui.xml && cat /data/local/tmp/ui.xml');
  }

  static Future<void> openApp(String packageName) async {
    LogService.command('openApp(shizuku): $packageName');
    final result = await exec(
      'am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER $packageName 2>/dev/null',
    );
    LogService.info('openApp(shizuku) result: ${result.length > 100 ? result.substring(0, 100) : result}');
  }

  static Future<List<Map<String, String>>> listInstalledApps() async {
    if (_cachedApps != null) return _cachedApps!;

    final result = await exec('pm list packages 2>/dev/null');
    final lines = result.split('\n');
    final apps = <Map<String, String>>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('package:')) continue;
      final pkg = trimmed.substring(8);
      if (pkg.isEmpty) continue;
      final parts = pkg.split('.');
      final label = parts.isNotEmpty ? parts.last : pkg;
      apps.add({'package': pkg, 'label': label});
    }

    _cachedApps = apps;
    return apps;
  }

  static Future<String?> findPackage(String query) async {
    final lower = query.toLowerCase();
    const known = {
      '微信': 'com.tencent.mm', 'wechat': 'com.tencent.mm',
      '支付宝': 'com.eg.android.AlipayGphone', 'alipay': 'com.eg.android.AlipayGphone',
      '淘宝': 'com.taobao.taobao', 'taobao': 'com.taobao.taobao',
      '京东': 'com.jingdong.app.mall',
      '美团': 'com.sankuai.meituan',
      '抖音': 'com.ss.android.ugc.aweme', 'douyin': 'com.ss.android.ugc.aweme',
      'qq': 'com.tencent.mobileqq',
      '百度': 'com.baidu.searchbox', 'baidu': 'com.baidu.searchbox',
      '高德': 'com.autonavi.minimap', '高德地图': 'com.autonavi.minimap',
      '网易云音乐': 'com.netease.cloudmusic',
      'b站': 'tv.danmaku.bili', 'bilibili': 'tv.danmaku.bili', '哔哩哔哩': 'tv.danmaku.bili',
      '小红书': 'com.xingin.xhs',
      '拼多多': 'com.xunmeng.pinduoduo',
      '知乎': 'com.zhihu.android',
      '饿了么': 'me.ele',
      '闲鱼': 'com.taobao.idlefish',
      '钉钉': 'com.alibaba.android.rimet',
      '微博': 'com.sina.weibo',
      '快手': 'com.sylq.kuaiShou',
      '酷狗': 'com.kugou.android',
      'QQ音乐': 'com.tencent.qqmusic',
      '爱奇艺': 'com.qiyi.video',
      '优酷': 'com.youku.phone',
      '腾讯视频': 'com.tencent.qqlive',
      '浏览器': 'com.android.chrome', 'chrome': 'com.android.chrome',
      '设置': 'com.android.settings', 'settings': 'com.android.settings',
      '计算器': 'com.android.calculator2',
      '日历': 'com.android.calendar',
      '时钟': 'com.android.deskclock',
      '相机': 'com.android.camera', 'camera': 'com.android.camera',
      '相册': 'com.android.gallery3d', '图库': 'com.android.gallery3d',
      '短信': 'com.android.mms', '信息': 'com.android.mms',
      '电话': 'com.android.dialer', '拨号': 'com.android.dialer',
      '联系人': 'com.android.contacts',
      '文件管理': 'com.android.documentsui', '文件': 'com.android.documentsui',
    };
    if (known.containsKey(lower)) return known[lower];
    if (known.containsKey(query)) return known[query];

    if (_cachedApps != null) {
      for (final app in _cachedApps!) {
        final pkg = app['package'] ?? '';
        final label = app['label'] ?? '';
        if (pkg.toLowerCase().contains(lower) || label.toLowerCase().contains(lower)) {
          return pkg;
        }
      }
    }

    try {
      final result = await exec("pm list packages 2>/dev/null | grep -i '$query' | head -5");
      final trimmed = result.trim();
      if (trimmed.startsWith('package:')) return trimmed.substring(8);
    } catch (_) {}

    try {
      final result = await exec("pm list packages -s 2>/dev/null | grep -i '$query' | head -1");
      final trimmed = result.trim();
      if (trimmed.startsWith('package:')) return trimmed.substring(8);
    } catch (_) {}

    return null;
  }
}
