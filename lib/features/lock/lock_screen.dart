import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/security/app_lock.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/noctwave_theme.dart';

/// Экран блокировки входа (ТЗ 3.2.5 «Приватность»): PIN-код и/или
/// FaceID/TouchID. Показывается при старте, если задан PIN или включена
/// биометрия.
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.settings,
    required this.onUnlocked,
  });

  final AppSettings settings;
  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final AppLock _lock = AppLock();
  final StringBuffer _pin = StringBuffer();
  String? _error;
  bool _biometricTried = false;

  @override
  void initState() {
    super.initState();
    if (widget.settings.biometricUnlock) {
      unawaited(_tryBiometric());
    }
  }

  Future<void> _tryBiometric() async {
    if (_biometricTried) return;
    _biometricTried = true;
    final ok = await _lock.authenticateBiometric();
    if (ok && mounted) widget.onUnlocked();
  }

  void _onDigit(String digit) {
    setState(() {
      _error = null;
      _pin.write(digit);
    });
    if (_pin.length >= 4) {
      _checkPin();
    }
  }

  void _checkPin() {
    final hash = widget.settings.appPinHash;
    if (hash == null) {
      widget.onUnlocked();
      return;
    }
    if (AppLock.verifyPin(_pin.toString(), hash)) {
      widget.onUnlocked();
    } else if (_pin.length >= 6) {
      setState(() {
        _error = 'Неверный PIN';
        _pin.clear();
      });
    }
  }

  void _onBackspace() {
    final s = _pin.toString();
    if (s.isEmpty) return;
    setState(() {
      _pin.clear();
      _pin.write(s.substring(0, s.length - 1));
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = NoctwaveColors.of(context);
    final hasPin = widget.settings.appPinHash != null;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              const Spacer(flex: 2),
              Icon(Icons.lock_outline, size: 48, color: colors.textSecondary),
              const SizedBox(height: 16),
              Text(
                'Noctwave заблокирован',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              if (hasPin)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List<Widget>.generate(6, (i) {
                    final filled = i < _pin.length;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled
                            ? Theme.of(context).colorScheme.primary
                            : colors.outline,
                      ),
                    );
                  }),
                ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(color: NoctwavePalette.stop)),
              ],
              const Spacer(flex: 2),
              if (widget.settings.biometricUnlock)
                TextButton.icon(
                  icon: Icon(Icons.fingerprint,
                      color: Theme.of(context).colorScheme.primary),
                  label: Text(
                    'FaceID / TouchID',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary),
                  ),
                  onPressed: () {
                    _biometricTried = false;
                    unawaited(_tryBiometric());
                  },
                ),
              if (hasPin) ...<Widget>[
                const SizedBox(height: 8),
                _keypad(colors),
              ],
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keypad(NoctwaveColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: <Widget>[
          for (final row in <List<String>>[
            <String>['1', '2', '3'],
            <String>['4', '5', '6'],
            <String>['7', '8', '9'],
            <String>['', '0', '⌫'],
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  for (final key in row)
                    SizedBox(
                      width: 72,
                      height: 52,
                      child: key.isEmpty
                          ? const SizedBox.shrink()
                          : TextButton(
                              onPressed: () {
                                if (key == '⌫') {
                                  _onBackspace();
                                } else {
                                  _onDigit(key);
                                }
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: colors.textPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(
                                key,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
