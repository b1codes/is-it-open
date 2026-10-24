import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/core/refractive_glass.dart';

void main() {
  testWidgets('frosts its child with a matching border', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RefractiveGlass(opacity: 0.1, borderRadius: 6, child: Text('g')),
      ),
    );
    expect(find.text('g'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    final decoration =
        tester.widget<Container>(find.byType(Container)).decoration!
            as BoxDecoration;
    expect(decoration.color, Colors.white.withValues(alpha: 0.1));
    expect(
      (decoration.border! as Border).top.color,
      Colors.white.withValues(alpha: 0.2),
    );
    expect(decoration.borderRadius, BorderRadius.circular(6));
  });
}
