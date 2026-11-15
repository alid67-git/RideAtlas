import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/base_map_style.dart';

/// Map-source (i) chip. Text follows the active language — the raw
/// [BaseMapStyle.attribution] field stays Turkish for storage/fallback
/// only and must not be shown while English (or German) is selected.
Widget rideAtlasMapAttribution(BuildContext context, BaseMapStyle style) {
  return SafeArea(
    top: false,
    left: false,
    right: false,
    child: RichAttributionWidget(
      attributions: [
        TextSourceAttribution(
          style.localizedAttribution(
            Localizations.localeOf(context).languageCode,
          ),
        ),
      ],
    ),
  );
}
