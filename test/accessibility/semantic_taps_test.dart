import 'dart:io';

import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/shell/presentation/widgets/bottom_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// A `Semantics(button: …, excludeSemantics: true)` replaces its child's
/// semantics — including the child's tap. Without its own `onTap`, a screen
/// reader announces a button that does nothing when activated. The tab bar
/// shipped like that: VoiceOver and TalkBack readers couldn't change tabs.
void main() {
  testWidgets('a screen reader can switch tabs', (tester) async {
    final semantics = tester.ensureSemantics();
    var selected = 3;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: BottomSwitcher(index: 3, onChanged: (i) => selected = i),
        ),
      ),
    );

    final node = tester.getSemantics(find.bySemanticsLabel('Search'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(find.semantics.byLabel('Search'));
    expect(selected, 0);
    semantics.dispose();
  });

  test('no button hides its own tap from assistive tech', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in RegExp(r'Semantics\(').allMatches(source)) {
        final rest = source.substring(match.end);
        final childAt = rest.indexOf('child:');
        if (childAt < 0) continue;
        final head = rest.substring(0, childAt);
        if (head.contains('button:') &&
            head.contains('excludeSemantics: true') &&
            !head.contains('onTap')) {
          final line = '\n'.allMatches(source.substring(0, match.start)).length;
          offenders.add('${file.path}:${line + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
