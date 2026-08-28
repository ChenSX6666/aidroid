import 'native_bridge.dart';
import 'log_service.dart';

class FileEntry {
  final String name;
  final bool isDirectory;
  final int? sizeBytes;
  final String? permissions;

  const FileEntry({
    required this.name,
    required this.isDirectory,
    this.sizeBytes,
    this.permissions,
  });
}

class FileStat {
  final bool exists;
  final int? sizeBytes;
  final String? permissions;
  final String? lastModified;

  const FileStat({
    required this.exists,
    this.sizeBytes,
    this.permissions,
    this.lastModified,
  });
}

class DeviceFileService {
  /// List directory contents using root
  static Future<List<FileEntry>> listDir(String path) async {
    try {
      final output = await NativeBridge.listDirectory(path);
      if (output.isEmpty) return [];
      return _parseLs(output);
    } catch (e) {
      LogService.error('listDir 失败: $e');
      return [];
    }
  }

  /// Read text file contents (max 64KB)
  static Future<String> readText(String path, {int maxBytes = 65536}) async {
    try {
      return await NativeBridge.readFile(path, maxBytes: maxBytes);
    } catch (e) {
      LogService.error('readFile 失败: $e');
      return '';
    }
  }

  /// Check if path exists
  static Future<bool> exists(String path) async {
    try {
      final stat = await NativeBridge.statFile(path);
      return stat.isNotEmpty && !stat.contains('No such file');
    } catch (_) {
      return false;
    }
  }

  /// Search files by name pattern
  static Future<List<String>> search(String rootPath, String pattern) async {
    try {
      final output = await NativeBridge.searchFiles(rootPath, pattern);
      if (output.isEmpty) return [];
      return output.split('\n').where((l) => l.isNotEmpty).take(50).toList();
    } catch (e) {
      LogService.error('searchFiles 失败: $e');
      return [];
    }
  }

  /// Get file info
  static Future<FileStat> stat(String path) async {
    try {
      final output = await NativeBridge.statFile(path);
      if (output.isEmpty || output.contains('No such file')) {
        return const FileStat(exists: false);
      }
      return _parseStat(output);
    } catch (_) {
      return const FileStat(exists: false);
    }
  }

  static List<FileEntry> _parseLs(String output) {
    final entries = <FileEntry>[];
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('total ')) continue;

      // Parse "drwxrwx--x 2 root root 4096 2024-01-01 12:00 dirname"
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 5) continue;

      try {
        final perms = parts[0];
        final isDir = perms.startsWith('d');
        final name = parts.sublist(5).join(' ');
        // Size is in parts[3] but symlinks have different format — use last numeric before date
        int? size = int.tryParse(parts.length > 6 ? parts[3] : parts[3]);
        if (size == null && parts.length > 6) {
          size = int.tryParse(parts[4]);
        }

        entries.add(FileEntry(
          name: name,
          isDirectory: isDir,
          sizeBytes: size,
          permissions: perms,
        ));
      } catch (_) {}
    }
    return entries;
  }

  static FileStat _parseStat(String output) {
    try {
      final lines = output.trim().split('\n');
      final firstLine = lines.firstWhere(
        (l) => l.contains(':') && !l.startsWith('File:'),
        orElse: () => '',
      );
      if (firstLine.isEmpty) return const FileStat(exists: false);

      int? size;
      for (final line in lines) {
        if (line.trim().startsWith('Size:')) {
          size = int.tryParse(line.split(':')[1].trim());
        }
      }
      return FileStat(exists: true, sizeBytes: size);
    } catch (_) {
      return const FileStat(exists: false);
    }
  }
}
