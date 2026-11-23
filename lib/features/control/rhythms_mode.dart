import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/engine/pattern_engine.dart';
import '../../core/models/device_profile.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/noctwave_theme.dart';

/// Режим «Ритмы» (ТЗ 4.3): библиотека локально сохранённых паттернов,
/// воспроизведение с Loop и скоростью 0.5x–2.0x, переименование/удаление.
class RhythmsMode extends StatefulWidget {
  const RhythmsMode({
    super.key,
    required this.device,
    required this.store,
    required this.onCommand,
  });

  final DeviceProfile device;
  final LocalStore store;
  final void Function(String channelId, String cmdHex) onCommand;

  @override
  State<RhythmsMode> createState() => _RhythmsModeState();
}

class _RhythmsModeState extends State<RhythmsMode> {
  late PatternPlayer _player;
  List<RecordedPattern> _patterns = <RecordedPattern>[];
  String? _playingId;
  bool _loop = true;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    _player = PatternPlayer(onCommand: widget.onCommand);
    _reload();
  }

  @override
  void dispose() {
    _player.stop();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _patterns = widget.store
          .loadPatterns()
          .where((p) => p.deviceId == widget.device.id)
          .toList();
    });
  }

  void _togglePlay(RecordedPattern pattern) {
    if (_playingId == pattern.id) {
      _player.stop();
      setState(() => _playingId = null);
      return;
    }
    _player.play(pattern, speed: _speed, loop: _loop);
    setState(() => _playingId = pattern.id);
  }

  Future<void> _rename(RecordedPattern pattern) async {
    final controller = TextEditingController(text: pattern.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Переименовать ритм'),
        content: TextField(controller: controller, autofocus: true),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final all = widget.store.loadPatterns();
    final idx = all.indexWhere((p) => p.id == pattern.id);
    if (idx < 0) return;
    final json = all[idx].toJson()..['name'] = name;
    all[idx] = RecordedPattern.fromJson(json);
    await widget.store.savePatterns(all);
    _reload();
  }

  Future<void> _delete(RecordedPattern pattern) async {
    if (_playingId == pattern.id) {
      _player.stop();
      _playingId = null;
    }
    final all =
        widget.store.loadPatterns().where((p) => p.id != pattern.id).toList();
    await widget.store.savePatterns(all);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_patterns.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.music_note_outlined,
                  size: 48, color: NoctwavePalette.textSecondary),
              const SizedBox(height: 12),
              const Text(
                'Ритмов пока нет.\nНажмите REC в доке, чтобы записать сессию,\n'
                'или сохраните жест в «Ритмы».',
                textAlign: TextAlign.center,
                style: TextStyle(color: NoctwavePalette.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: <Widget>[
              FilterChip(
                label: const Text('Loop'),
                selected: _loop,
                onSelected: (v) => setState(() => _loop = v),
              ),
              const Spacer(),
              DropdownButton<double>(
                value: _speed,
                items: const <DropdownMenuItem<double>>[
                  DropdownMenuItem(value: 0.5, child: Text('0.5x')),
                  DropdownMenuItem(value: 1.0, child: Text('1.0x')),
                  DropdownMenuItem(value: 1.5, child: Text('1.5x')),
                  DropdownMenuItem(value: 2.0, child: Text('2.0x')),
                ],
                onChanged: (v) => setState(() => _speed = v ?? 1.0),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _patterns.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final p = _patterns[i];
              final playing = _playingId == p.id;
              return Card(
                child: ListTile(
                  leading: Icon(
                    playing ? Icons.pause_circle : Icons.play_circle_outline,
                    color: playing
                        ? NoctwavePalette.accentHigh
                        : Theme.of(context).colorScheme.primary,
                    size: 36,
                  ),
                  title: Text(p.name),
                  subtitle: Text(
                    '${p.events.length} событий · '
                    '${(p.durationMs / 1000).toStringAsFixed(1)} с',
                  ),
                  onTap: () => _togglePlay(p),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) {
                      switch (action) {
                        case 'rename':
                          unawaited(_rename(p));
                        case 'delete':
                          unawaited(_delete(p));
                      }
                    },
                    itemBuilder: (context) => const <PopupMenuEntry<String>>[
                      PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                      PopupMenuItem(value: 'delete', child: Text('Удалить')),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
