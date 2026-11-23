package com.noctwave.noctwave_app

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(BleAdvertiserPlugin())
        flutterEngine.plugins.add(SystemControlsPlugin())
    }

    /**
     * «Громкость вниз» = экстренный СТОП (ТЗ 3.2.4 / 3.2.5).
     * Событие уходит в Dart; фильтрация по настройке volumeDownStop
     * выполняется на стороне приложения. Громкость при этом не меняется,
     * только пока обработчик активен в Dart — иначе пропускаем дальше.
     */
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            SystemControlsPlugin.instance?.notifyVolumeDown()
        }
        return super.onKeyDown(keyCode, event)
    }
}
