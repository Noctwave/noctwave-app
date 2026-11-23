import 'dart:convert';

/// Импорт локальных файлов .funscript (ТЗ 4.5): JSON-массив
/// `actions: [{at, pos}]`, где pos ∈ [0, 100] → ступень мощности.
class Funscript {
  const Funscript({required this.actions});

  final List<FunscriptAction> actions;

  factory Funscript.parse(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final raw = (json['actions'] as List<dynamic>?) ?? <dynamic>[];
    final actions = raw
        .map((e) => FunscriptAction.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.atMs.compareTo(b.atMs));
    return Funscript(actions: actions);
  }

  /// Значение pos ∈ [0, 1] для момента [atMs] (линейная интерполяция
  /// между соседними ключевыми точками).
  double positionAt(int atMs) {
    if (actions.isEmpty) return 0;
    if (atMs <= actions.first.atMs) return actions.first.pos / 100;
    if (atMs >= actions.last.atMs) return actions.last.pos / 100;
    // Бинарный поиск соседних точек.
    var lo = 0;
    var hi = actions.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (actions[mid].atMs <= atMs) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = actions[lo];
    final b = actions[hi];
    if (b.atMs == a.atMs) return a.pos / 100;
    final t = (atMs - a.atMs) / (b.atMs - a.atMs);
    return ((a.pos + (b.pos - a.pos) * t) / 100).clamp(0.0, 1.0);
  }

  int get durationMs => actions.isEmpty ? 0 : actions.last.atMs;
}

class FunscriptAction {
  const FunscriptAction({required this.atMs, required this.pos});

  final int atMs;

  /// Позиция 0..100 (ТЗ 4.5).
  final int pos;

  factory FunscriptAction.fromJson(Map<String, dynamic> json) =>
      FunscriptAction(
        atMs: (json['at'] as num).toInt(),
        pos: (json['pos'] as num).toInt().clamp(0, 100),
      );
}
