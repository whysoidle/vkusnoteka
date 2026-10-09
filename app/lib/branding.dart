import 'package:flutter/widgets.dart';

const appName = 'Вкуснотека';

class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/app_icon.png',
    width: size,
    height: size,
    cacheWidth: 128,
    excludeFromSemantics: true,
  );
}
