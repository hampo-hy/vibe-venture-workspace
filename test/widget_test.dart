// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:vibeventure/main.dart';

void main() {
  testWidgets('Shows app shell with bottom navigation tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const YonggongiApp());

    expect(find.text('영공이'), findsOneWidget);
    expect(find.text('바로가기'), findsOneWidget);
    expect(find.text('홈'), findsWidgets);
    expect(find.text('출결'), findsOneWidget);
    expect(find.text('상벌점'), findsOneWidget);
    expect(find.text('마이'), findsOneWidget);

    await tester.tap(find.text('출결'));
    await tester.pumpAndSettle();

    expect(find.text('오늘 출결'), findsWidgets);
  });
}
