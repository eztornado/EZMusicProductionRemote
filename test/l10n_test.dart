import 'package:ezmusicproduction_remote/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves system language preferences', () {
    expect(
      resolveLanguage(AppLanguage.system, const Locale('es', 'ES')),
      AppLanguage.spanish,
    );
    expect(
      resolveLanguage(AppLanguage.system, const Locale('ja', 'JP')),
      AppLanguage.japanese,
    );
    expect(
      resolveLanguage(AppLanguage.system, const Locale('fr', 'FR')),
      AppLanguage.english,
    );
    expect(
      resolveLanguage(AppLanguage.spanish, const Locale('ja', 'JP')),
      AppLanguage.spanish,
    );
  });

  test('ships English, Spanish and Japanese strings', () {
    expect(L10n.forLanguage(AppLanguage.english).t('mixerTitle'), 'Mixer');
    expect(L10n.forLanguage(AppLanguage.spanish).t('mixerTitle'), 'Mezclador');
    expect(L10n.forLanguage(AppLanguage.japanese).t('mixerTitle'), 'ミキサー');
  });

  test('ships the synth and settings sections in every language', () {
    final en = L10n.forLanguage(AppLanguage.english);
    final es = L10n.forLanguage(AppLanguage.spanish);
    final ja = L10n.forLanguage(AppLanguage.japanese);
    expect(en.t('navigationSynth'), 'Synth');
    expect(es.t('navigationSynth'), 'Synth');
    expect(ja.t('navigationSynth'), 'シンセ');
    expect(en.t('interfaceSection'), 'Interface');
    expect(es.t('interfaceSection'), 'Interfaz');
    expect(ja.t('interfaceSection'), 'インターフェース');
    expect(es.t('presetSection'), 'Presets');
    expect(ja.t('presetSection'), 'プリセット');
  });

  test('interpolates named placeholders', () {
    expect(
      L10n.forLanguage(AppLanguage.english).t('channelCount', {'count': 3}),
      '3 channels',
    );
    expect(
      L10n.forLanguage(AppLanguage.spanish).t('channelCount', {'count': 3}),
      '3 canales',
    );
  });

  test('falls back to the key for unknown strings', () {
    expect(L10n.fallback.t('missing.key'), 'missing.key');
  });

  test('language codes round-trip', () {
    for (final language in AppLanguage.values) {
      expect(languageFromCode(languageCode(language)), language);
    }
    expect(languageFromCode('xx'), AppLanguage.system);
  });
}
