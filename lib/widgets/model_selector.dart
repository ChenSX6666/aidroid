import 'package:flutter/material.dart';
import '../models/ai_provider.dart';

class ModelSelector extends StatefulWidget {
  final String selectedProviderId;
  final String selectedModelId;
  final List<AiProvider> providers;
  final void Function(String) onProviderChanged;
  final void Function(String) onModelChanged;
  final List<Widget>? trailingActions;

  const ModelSelector({
    super.key,
    required this.selectedProviderId,
    required this.selectedModelId,
    required this.providers,
    required this.onProviderChanged,
    required this.onModelChanged,
    this.trailingActions,
  });

  @override
  State<ModelSelector> createState() => _ModelSelectorState();
}

class _ModelSelectorState extends State<ModelSelector> {
  List<String> _models = [];
  bool _loading = false;

  AiProvider get _currentProvider {
    return widget.providers.firstWhere(
      (p) => p.id == widget.selectedProviderId,
      orElse: () => widget.providers.first,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  @override
  void didUpdateWidget(ModelSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedProviderId != widget.selectedProviderId) {
      _loadModels();
    }
  }

  Future<void> _loadModels() async {
    setState(() => _loading = true);
    try {
      final models = await _currentProvider.getAllModels();
      if (mounted) {
        setState(() {
          _models = models;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _models = _currentProvider.defaultModels;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showTrailing = widget.trailingActions != null && widget.trailingActions!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : const Color(0xFFF9FAFB),
        border: Border(
          top: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (showTrailing) ...[
              ...widget.trailingActions!,
              const SizedBox(width: 6),
              Container(width: 1, height: 16, color: isDark ? Colors.white12 : Colors.black12),
              const SizedBox(width: 6),
            ],
            _buildProviderDropdown(context, isDark),
            const SizedBox(width: 6),
            Container(width: 1, height: 16, color: isDark ? Colors.white12 : Colors.black12),
            const SizedBox(width: 6),
            _buildModelDropdown(context, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderDropdown(BuildContext context, bool isDark) {
    return SizedBox(
      width: 105,
      child: PopupMenuButton<String>(
        offset: const Offset(0, -300),
        onSelected: (id) {
          widget.onProviderChanged(id);
          final provider = widget.providers.firstWhere((p) => p.id == id);
          if (provider.defaultModels.isNotEmpty) {
            widget.onModelChanged(provider.defaultModels.first);
          }
        },
        itemBuilder: (_) => widget.providers.map((p) {
          return PopupMenuItem(
            value: p.id,
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: p.color,
                  radius: 12,
                  child: Text(p.name[0], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                Text(p.name, style: const TextStyle(fontSize: 13)),
                if (p.id == widget.selectedProviderId)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.check, size: 16, color: Color(0xFF0D7CB5)),
                  ),
              ],
            ),
          );
        }).toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.black12,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                backgroundColor: _currentProvider.color,
                radius: 8,
                child: Text(_currentProvider.name[0], style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  _currentProvider.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black87),
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelDropdown(BuildContext context, bool isDark) {
    return SizedBox(
      width: 145,
      child: PopupMenuButton<String>(
        offset: const Offset(0, -300),
        onSelected: widget.onModelChanged,
        itemBuilder: (_) {
          if (_loading) {
            return [
              const PopupMenuItem(
                enabled: false,
                value: '',
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ];
          }
          return _models.map((m) {
            return PopupMenuItem(
              value: m,
              child: Row(
                children: [
                  Text(m, style: const TextStyle(fontSize: 13)),
                  if (m == widget.selectedModelId)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.check, size: 16, color: Color(0xFF0D7CB5)),
                    ),
                ],
              ),
            );
          }).toList();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.black12,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              else
                Flexible(
                  child: Text(
                    widget.selectedModelId,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              const Icon(Icons.arrow_drop_down, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}
