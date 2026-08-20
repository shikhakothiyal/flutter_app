import 'package:flutter_test/flutter_test.dart';
import 'package:pulsesync_mobile/main.dart';

void main() {
  testWidgets('PulseSync Mobile App Smoke Test', (WidgetTester tester) async {
    await tester.pumpWidget(const PulseSyncMobileApp());
    expect(find.text('PulseSync'), findsOneWidget);
  });
}
