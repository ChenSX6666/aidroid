class LogService {
  LogService._();

  static final _buffer = <String>[];
  static const _maxLines = 500;
  static DateTime? _startTime;

  static void _add(String msg) {
    _startTime ??= DateTime.now();
    final ts = DateTime.now().difference(_startTime!).toString().split('.').first;
    _buffer.add('[$ts] $msg');
    while (_buffer.length > _maxLines) {
      _buffer.removeAt(0);
    }
  }

  static void info(String msg) => _add('[INFO] $msg');
  static void error(String msg) => _add('[ERROR] $msg');
  static void agent(String msg) => _add('[AGENT] $msg');
  static void command(String cmd) => _add('[CMD] $cmd');

  static String dump() => _buffer.join('\n');

  static void clear() {
    _buffer.clear();
    _startTime = null;
  }
}
