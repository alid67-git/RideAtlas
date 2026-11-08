import 'package:flutter_test/flutter_test.dart';
import 'package:rideatlas/build_info.dart';
import 'package:rideatlas/changelog.dart';
import 'package:rideatlas/models/base_map_style.dart';

void main() {
  test('latest changelog entry matches the running build label', () {
    expect(kChangelog, isNotEmpty);
    expect(kChangelog.first.version, kAppBuildLabel);
  });

  test('version history and what’s-new follow the selected language', () {
    final englishUi = kChangelog.firstWhere(
      (e) => e.version == 'v1.4.130 beta',
    );
    expect(englishUi.noteFor('tr'), contains('İngilizce'));
    expect(englishUi.noteFor('en'), contains('English'));
    expect(englishUi.noteFor('de'), englishUi.noteFor('en'));
    expect(englishUi.noteFor('en'), isNot(contains('Türkçe')));

    expect(localizedBuildNote('tr'), kAppBuildNoteTr);
    expect(localizedBuildNote('en'), kAppBuildNoteEn);
    expect(localizedBuildNote('de'), kAppBuildNoteEn);
    expect(localizedBuildNote('en'), isNot(contains('katkıda')));
  });

  test('every changelog row has both Turkish and English notes', () {
    for (final entry in kChangelog) {
      expect(entry.noteTr, isNotEmpty, reason: entry.version);
      expect(entry.noteEn, isNotEmpty, reason: entry.version);
      expect(entry.noteFor('tr'), entry.noteTr, reason: entry.version);
      expect(entry.noteFor('en'), entry.noteEn, reason: entry.version);
    }
  });

  test('map attribution is English when the UI language is English', () {
    final street = findBaseMapStyle('voyager');
    expect(street.localizedAttribution('tr'), contains('katkıda'));
    expect(street.localizedAttribution('en'), 'OpenStreetMap contributors');
    expect(street.localizedAttribution('de'), 'OpenStreetMap-Mitwirkende');
    expect(
      findBaseMapStyle('topo').localizedAttribution('en'),
      contains('OpenStreetMap contributors'),
    );
  });
}
