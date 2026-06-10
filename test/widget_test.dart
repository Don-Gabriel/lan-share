import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/main.dart';

void main() {
  testWidgets('shows the branded splash screen', (tester) async {
    await tester.pumpWidget(const LanShareApp());

    expect(find.text('LAN Share'), findsOneWidget);
    expect(find.text('Starting...'), findsOneWidget);
  });
}
