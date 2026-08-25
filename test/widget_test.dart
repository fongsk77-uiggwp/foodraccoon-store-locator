import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:foodraccoon_store_locator/main.dart';

void main() {
  testWidgets('loads the Store Locator mobile layout', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const FoodRaccoonApp());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await tester.pump();

    expect(find.text('FoodRaccoon'), findsOneWidget);
    expect(find.text('Search stores or areas'), findsOneWidget);
    expect(find.text('Map view'), findsOneWidget);
    expect(find.text('Nearby stores'), findsOneWidget);
    expect(find.byTooltip('Set location'), findsOneWidget);
    expect(find.byTooltip('Filter and sort'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'puchong');
    await tester.pump();
    expect(find.byTooltip('Clear search'), findsOneWidget);
    expect(find.byKey(const Key('store-search-suggestions')), findsOneWidget);
    await tester.tap(find.text('TESCO PUCHONG').first);
    await tester.pump();
    expect(find.text('TESCO PUCHONG'), findsWidgets);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.byTooltip('Clear search'), findsNothing);

    await tester.tap(find.byTooltip('Filter and sort'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Filter and sort'), findsOneWidget);
    expect(find.text('Nearest first'), findsOneWidget);
    expect(find.text('Name A–Z'), findsOneWidget);
    expect(find.text('Most price data'), findsOneWidget);
    expect(find.text('Store type'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Supermarket'), findsOneWidget);
    expect(find.text('Hypermarket'), findsOneWidget);
    expect(find.text('Fresh Market'), findsOneWidget);
    expect(find.text('Grocery Shop'), findsOneWidget);
    expect(find.text('Mini Market'), findsOneWidget);
    expect(find.text('Open now'), findsWidgets);
    expect(find.text('Has price data'), findsOneWidget);
    Navigator.of(tester.element(find.text('Filter and sort'))).pop();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('View prices'), findsWidgets);
    expect(find.byTooltip('Get directions'), findsWidgets);

    await tester.tap(find.text('View prices').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Price information'), findsOneWidget);
    expect(find.text('Open route'), findsOneWidget);
    expect(find.text('Tap to open route'), findsOneWidget);
    Navigator.of(tester.element(find.text('Price information'))).pop();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byTooltip('Set location'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Choose your location'), findsOneWidget);
    expect(find.text('Tap map to drop a pin'), findsOneWidget);
    expect(find.text('Enter a place or address'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'wangsa');
    await tester.pump();
    expect(find.text('Wangsa Maju, Kuala Lumpur'), findsWidgets);
    expect(find.text('Location area'), findsWidgets);
    expect(find.text('AEON ( WANGSA MAJU )'), findsNothing);

    await tester.enterText(find.byType(TextField).last, 'puchong');
    await tester.pump();
    expect(find.text('Puchong, Selangor'), findsOneWidget);
  });
}
