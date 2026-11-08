import '../services/track_io.dart';
import 'gen/app_localizations.dart';

String importFormatErrorMessage(AppLocalizations l10n, FormatException error) {
  return isKmzMissingKml(error) ? l10n.kmzMissingKml : l10n.trackHasNoPoints;
}
