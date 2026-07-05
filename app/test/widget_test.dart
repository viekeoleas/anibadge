import 'package:flutter_test/flutter_test.dart';

import 'package:znachok_bmw/main.dart';

void main() {
  testWidgets('shows disconnected start screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ZnachokApp());

    expect(find.text('Подключиться'), findsOneWidget);
    expect(find.text('Не подключено'), findsOneWidget);
  });
}
