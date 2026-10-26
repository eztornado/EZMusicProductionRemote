import 'package:ezmusicproduction_remote/l10n/strings.dart';
import 'package:ezmusicproduction_remote/theme/app_theme.dart';
import 'package:ezmusicproduction_remote/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('brand, badge and toggle render and respond to taps', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      L10nScope(
        l10n: L10n.forLanguage(AppLanguage.english),
        language: AppLanguage.english,
        onLanguageChanged: (_) {},
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Column(
              children: [
                const BrandMark(),
                CountBadge(L10n.fallback.t('channelCount', {'count': 4})),
                ToggleTag(
                  label: 'M',
                  active: true,
                  tooltip: L10n.fallback.t('mute'),
                  onTap: () => tapped = true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('4 channels'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    expect(find.byType(BrandMark), findsOneWidget);

    await tester.tap(find.text('M'));
    await tester.pump();
    expect(tapped, isTrue);
  });
}
