import 'package:anytime/ui/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dynamic light theme uses a fallback color scheme when absent', () {
    final theme = Themes.dynamicLightTheme(null).themeData;

    expect(theme.brightness, Brightness.light);
    expect(
      theme.colorScheme.primary,
      ColorScheme.fromSeed(seedColor: Colors.deepPurple).primary,
    );
  });

  test('dynamic dark theme uses a fallback color scheme when absent', () {
    final theme = Themes.dynamicDarkTheme(null).themeData;

    expect(theme.brightness, Brightness.dark);
    expect(
      theme.colorScheme.primary,
      ColorScheme.fromSeed(seedColor: Colors.deepPurple).primary,
    );
  });

  testWidgets('system theme follows device brightness changes', (tester) async {
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    late ThemeData themeBeforeBrightnessChange;
    late ThemeData themeAfterBrightnessChange;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: ThemeMode.system,
        home: Builder(
          builder: (context) => Text(
            Theme.of(context).brightness.name,
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    );

    expect(find.text('light'), findsOneWidget);
    themeBeforeBrightnessChange = Theme.of(
      tester.element(find.byType(Text)),
    );

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();

    expect(find.text('dark'), findsOneWidget);
    themeAfterBrightnessChange = Theme.of(tester.element(find.byType(Text)));
    expect(themeBeforeBrightnessChange.brightness, Brightness.light);
    expect(themeAfterBrightnessChange.brightness, Brightness.dark);
  });
}
