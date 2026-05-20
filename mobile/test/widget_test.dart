import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hanapgawa/main.dart';

void main() {
  testWidgets('renders HanapGawa onboarding screen',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const HanapGawaApp());
    await tester.pump(const Duration(milliseconds: 2600));

    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
  });
}
