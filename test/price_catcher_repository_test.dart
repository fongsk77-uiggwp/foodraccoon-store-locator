import 'package:flutter_test/flutter_test.dart';

import 'package:foodraccoon_store_locator/data/price_catcher_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'keeps grocery premises, enriches locality, and excludes food service',
    () async {
      final snapshot = await PriceCatcherRepository().loadSnapshot();

      expect(snapshot.stores, isNotEmpty);
      expect(
        snapshot.stores.every((store) {
          final type = store.type.toLowerCase();
          return !type.startsWith('restoran') &&
              type != 'foodcourt' &&
              type != 'medan selera';
        }),
        isTrue,
      );
      expect(snapshot.stores.any((store) => store.postcode.isNotEmpty), isTrue);
      expect(snapshot.stores.any((store) => store.city.isNotEmpty), isTrue);
      expect(
        snapshot.locationAreas.any(
          (area) => area.city == 'Puchong' && area.state == 'Selangor',
        ),
        isTrue,
      );
    },
  );

  test('calculates open status from the published opening hours', () async {
    final snapshot = await PriceCatcherRepository().loadSnapshot();
    final store = snapshot.stores.firstWhere(
      (store) => store.openingHours == '08:00–22:00',
    );

    expect(store.isOpenAt(DateTime(2026, 8, 23, 0)), isFalse);
    expect(store.isOpenAt(DateTime(2026, 8, 23, 8)), isTrue);
    expect(store.isOpenAt(DateTime(2026, 8, 23, 22)), isFalse);
  });
}
