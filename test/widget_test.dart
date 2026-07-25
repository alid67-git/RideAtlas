import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rideatlas/main.dart';

void main() {
  testWidgets('shows the empty route list on first launch', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const RideAtlasApp());
    await tester.pumpAndSettle();

    expect(find.text('RideAtlas'), findsOneWidget);
    expect(find.text('Henüz rota yok'), findsOneWidget);
    expect(find.text('GPX İçe Aktar'), findsWidgets);
  });
}
