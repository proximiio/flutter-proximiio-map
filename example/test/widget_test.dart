import 'package:flutter_proximiio_map_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('without a token the app explains how to pass one', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.textContaining('--dart-define-from-file'), findsOneWidget);
  });
}
