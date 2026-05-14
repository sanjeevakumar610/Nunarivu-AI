import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nunarivu_ai/main.dart';

void main() {
  testWidgets('App boots and shows a loading or onboarding state',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: NunarivuApp()));
    // Just verify no crashes during initial frame
    await tester.pump();
  });
}
