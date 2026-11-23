import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'core/storage/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LocalStore.open();
  runApp(NoctwaveApp(store: store));
}
