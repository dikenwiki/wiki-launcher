import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_launcher/main_android.dart';

void main() {
  testWidgets('Launcher smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const WikiLauncherApp());
    expect(find.byType(WikiLauncherApp), findsOneWidget);
  });
}
