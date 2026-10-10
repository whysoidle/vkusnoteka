import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/page_list.dart';
import '../widgets/recipe_text.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/recipe.dart';
import '../services/recipe_tools.dart';
import '../services/timer_alarm.dart';
import '../widgets/desktop_swipe.dart';

class CookingTimer {
  final String label;
  final DateTime end;
  final DateTime Function() _now;
  bool announced = false;
  CookingTimer(this.label, Duration duration, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      end = (now ?? DateTime.now)().add(duration);
  Duration get remaining {
    final duration = end.difference(_now());
    return duration.isNegative ? Duration.zero : duration;
  }
}

class CookingScreen extends StatefulWidget {
  final Recipe recipe;
  final TimerAlarm alarm;
  final DateTime Function()? now;
  const CookingScreen({
    super.key,
    required this.recipe,
    this.alarm = const TimerAlarm(),
    this.now,
  });
  @override
  State<CookingScreen> createState() => _CookingScreenState();
}

class _CookingScreenState extends State<CookingScreen>
    with WidgetsBindingObserver {
  int step = 0;
  bool keepAwake = true;
  String wakeError = '';
  String soundError = '';
  final timers = <CookingTimer>[];
  Timer? ticker;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    screenLock(true);
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final expired = <CookingTimer>[];
      for (final timer in timers) {
        if (timer.remaining == Duration.zero && !timer.announced) {
          timer.announced = true;
          expired.add(timer);
        }
      }
      if (expired.isNotEmpty) {
        playAlarm();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              expired.length == 1
                  ? '${expired.single.label}: время вышло'
                  : 'Время вышло: ${expired.length} таймера',
            ),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Остановить звук',
              onPressed: stopAlarm,
            ),
          ),
        );
      }
      if (timers.isNotEmpty) setState(() {});
    });
  }

  Future<void> playAlarm() async {
    try {
      await widget.alarm.play();
      if (mounted && soundError.isNotEmpty) setState(() => soundError = '');
    } catch (error) {
      if (mounted) {
        setState(
          () => soundError = error is PlatformException && error.message != null
              ? error.message!
              : 'Не удалось воспроизвести сигнал. Проверьте громкость звука и повторите проверку.',
        );
      }
    }
  }

  Future<void> stopAlarm() => widget.alarm.stop().catchError((Object _) {});

  Future<void> screenLock(bool enabled) async {
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (_) {
      if (mounted && enabled) {
        setState(
          () => wakeError =
              'Не удалось удержать экран включённым. Проверьте системный тайм-аут экрана.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    screenLock(keepAwake && state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    screenLock(false);
    stopAlarm();
    super.dispose();
  }

  void start(Duration duration) => setState(
    () =>
        timers.add(CookingTimer('Шаг ${step + 1}', duration, now: widget.now)),
  );
  void changeStep(int delta) {
    final next = step + delta;
    if (next >= 0 && next < widget.recipe.steps.length) {
      setState(() => step = next);
    }
  }

  Future<void> customTimer() async {
    final input = TextEditingController(text: '5');
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Таймер'),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Минуты, от 1 до 1440'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(input.text);
              if (n != null && n > 0 && n <= 1440) Navigator.pop(context, n);
            },
            child: const Text('Запустить'),
          ),
        ],
      ),
    );
    input.dispose();
    if (minutes != null && mounted) start(Duration(minutes: minutes));
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.recipe.steps, c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.recipe.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: DesktopSwipe(
        onLeft: () => changeStep(1),
        onRight: () => changeStep(-1),
        child: PageList(
          maxWidth: 820,
          listKey: ValueKey('cooking-step-$step'),
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Шаг ${step + 1} из ${steps.length}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (isDesktopNavigation(context)) ...[
              Text(
                'Листайте шаги влево и вправо',
                style: TextStyle(color: c.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
            ],
            LinearProgressIndicator(value: (step + 1) / steps.length),
            const SizedBox(height: 28),
            RecipeText(
              steps[step],
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final duration in stepDurations(steps[step]))
                  FilledButton.tonalIcon(
                    onPressed: () => start(duration),
                    icon: const Icon(Icons.timer_outlined),
                    label: Text(
                      'Таймер ${duration.inSeconds < 60 ? '${duration.inSeconds} сек' : '${duration.inMinutes} мин'}',
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: customTimer,
                  icon: const Icon(Icons.add_alarm),
                  label: const Text('Свой таймер'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            for (final timer in timers)
              Card(
                color: timer.remaining == Duration.zero
                    ? c.tertiaryContainer
                    : c.surfaceContainerLow,
                child: ListTile(
                  leading: const Icon(Icons.timer),
                  title: Text(timer.label),
                  subtitle: Text(
                    timer.remaining == Duration.zero
                        ? 'Время вышло'
                        : '${timer.remaining.inMinutes.toString().padLeft(2, '0')}:${(timer.remaining.inSeconds % 60).toString().padLeft(2, '0')}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Удалить таймер',
                    onPressed: () {
                      if (timer.announced) stopAlarm();
                      setState(() => timers.remove(timer));
                    },
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Не выключать экран'),
              value: keepAwake,
              onChanged: (value) {
                setState(() => keepAwake = value);
                screenLock(value);
              },
            ),
            if (wakeError.isNotEmpty) Text(wakeError),
            TextButton.icon(
              onPressed: playAlarm,
              icon: const Icon(Icons.volume_up_outlined),
              label: const Text('Проверить звук таймера'),
            ),
            if (soundError.isNotEmpty) Text(soundError),
            const Text(
              'Таймеры работают, пока открыт режим готовки. При выходе таймеры сбрасываются.',
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: step == 0 ? null : () => setState(() => step--),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Назад'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    if (step == steps.length - 1) {
                      Navigator.pop(context);
                    } else {
                      setState(() => step++);
                    }
                  },
                  child: Text(
                    step == steps.length - 1 ? 'Готово' : 'Следующий шаг',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
