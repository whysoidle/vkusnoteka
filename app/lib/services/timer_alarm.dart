import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TimerAlarm {
  final TargetPlatform? platform;
  const TimerAlarm({this.platform});
  static const channel = MethodChannel('recipe_vault/timer_alarm');
  TargetPlatform get target => platform ?? defaultTargetPlatform;

  Future<void> play() async {
    if (!kIsWeb && target == TargetPlatform.android) {
      await channel.invokeMethod<void>('play');
    } else {
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> stop() async {
    if (!kIsWeb && target == TargetPlatform.android) {
      await channel.invokeMethod<void>('stop');
    }
  }
}
