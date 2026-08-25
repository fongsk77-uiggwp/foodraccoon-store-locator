import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/price_catcher_repository.dart';
import '../main.dart';
import '../models/location_area.dart';
import '../models/store.dart';
import '../services/location_service.dart';

class StoreLocatorScreen extends StatefulWidget {
  const StoreLocatorScreen({super.key});

  @override
  State<StoreLocatorScreen> createState() => _StoreLocatorScreenState();
}

enum _StoreSortOption { nearest, name, mostPriceData }

class _StoreLocatorScreenState extends State<StoreLocatorScreen> {
  static const _defaultLocation = LatLng(3.2090, 101.7250);

  final _repository = PriceCatcherRepository();
  final _locationService = LocationService();
  final _searchController = TextEditingController();
  final _mapController = MapController();
  late final Future<PriceCatcherSnapshot> _snapshotFuture;
  Timer? _statusRefreshTimer;

  LatLng _userLocation = _defaultLocation;
  String _locationLabel = 'TAR UMT, Setapak';
  String _query = '';
  String _selectedType = 'All';
  bool _showMap = true;
  bool _showMoreStores = false;
  bool _usingDeviceLocation = false;
  _StoreSortOption _sortOption = _StoreSortOption.nearest;
  bool _openNowOnly = false;
  bool _hasPriceDataOnly = false;
  List<LocationArea> _locationAreas = const [];
  @override
  void initState() {
    super.initState();
    _snapshotFuture = _repository.loadSnapshot().then((snapshot) {
      _locationAreas = snapshot.locationAreas;
      return snapshot;
    });
    _statusRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _statusRefreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: foodRaccoonGreen,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.pets_outlined,
                color: Colors.white,
                size: 21,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'FoodRaccoon',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Set location',
            onPressed: _openLocationPicker,
            icon: const Icon(Icons.my_location_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<PriceCatcherSnapshot>(
        future: _snapshotFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _ErrorState(onRetry: () => setState(() {}));
          }
          return _buildContent(snapshot.data!);
        },
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 820
          ? NavigationBar(
              selectedIndex: _showMap ? 0 : 1,
              onDestinationSelected: (index) {
                setState(() => _showMap = index == 0);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map),
                  label: 'Map view',
                ),
                NavigationDestination(
                  icon: Icon(Icons.format_list_bulleted),
                  selectedIcon: Icon(Icons.view_list),
                  label: 'Store list',
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildContent(PriceCatcherSnapshot snapshot) {
    final stores = _filteredStores(snapshot.stores);
    return SafeArea(
      child: Column(
        children: [
          _buildSearchAndFilters(snapshot),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 820) {
                  return Row(
                    children: [
                      Expanded(flex: 6, child: _buildMap(stores)),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 4,
                        child: _buildStoreList(stores, snapshot),
                      ),
                    ],
                  );
                }
                if (!_showMap) {
                  return _buildStoreList(stores, snapshot);
                }
                return _buildMobileMapView(stores);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileMapView(List<Store> stores) {
    return Column(
      children: [
        SizedBox(
          height: math.min(360, MediaQuery.sizeOf(context).height * 0.42),
          child: _buildMap(
            stores,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          ),
        ),
        Expanded(child: _buildNearestStorePanel(stores)),
      ],
    );
  }

  Widget _buildNearestStorePanel(List<Store> stores) {
    if (stores.isEmpty) {
      return const Center(child: Text('No stores match your search.'));
    }
    final visibleStores = _showMoreStores ? stores : stores.take(5).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Nearby stores',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              Flexible(
                child: Text(
                  '${stores.length} found • ${_sortLabel.toLowerCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        ...visibleStores.map(_buildStoreCard),
        if (stores.length > 5)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: OutlinedButton.icon(
              onPressed: () =>
                  setState(() => _showMoreStores = !_showMoreStores),
              icon: Icon(
                _showMoreStores ? Icons.expand_less : Icons.expand_more,
              ),
              label: Text(
                _showMoreStores
                    ? 'Show fewer stores'
                    : 'Show more stores (${stores.length - 5})',
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchAndFilters(PriceCatcherSnapshot snapshot) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() {
                    _query = value;
                    _showMoreStores = false;
                  }),
                  decoration: InputDecoration(
                    hintText: 'Search stores or areas',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_query.trim().isNotEmpty)
                          IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _query = '';
                                _showMoreStores = false;
                              });
                            },
                            icon: const Icon(Icons.close),
                          ),
                        IconButton(
                          tooltip: 'Filter and sort',
                          onPressed: _openFilterSheet,
                          icon: const Icon(Icons.tune_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          _buildSearchSuggestions(snapshot.stores),
        ],
      ),
    );
  }

  Widget _buildSearchSuggestions(List<Store> stores) {
    final suggestions = _searchSuggestions(stores);
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        key: const Key('store-search-suggestions'),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FBF8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDCE9E2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 10, 12, 3),
              child: Text(
                'Suggestions',
                style: TextStyle(
                  color: foodRaccoonGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (var index = 0; index < suggestions.length; index++) ...[
              InkWell(
                onTap: () => _selectSearchSuggestion(suggestions[index]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _storeSuggestionIcon(suggestions[index]),
                        color: foodRaccoonBright,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              suggestions[index].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${suggestions[index].type} • ${_storeSuggestionSubtitle(suggestions[index])}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.north_west, size: 16),
                    ],
                  ),
                ),
              ),
              if (index != suggestions.length - 1)
                const Divider(height: 1, indent: 42, endIndent: 12),
            ],
          ],
        ),
      ),
    );
  }

  List<Store> _searchSuggestions(List<Store> stores) {
    final query = _query.trim().toLowerCase();
    if (query.length < 2) return const [];

    final matches = stores.where((store) {
      final searchText = _storeSearchText(store);
      return _matchesStoreType(store) &&
          (!_openNowOnly || store.isOpenNow) &&
          (!_hasPriceDataOnly || store.hasPriceData) &&
          searchText.contains(query);
    }).toList();
    matches.sort((first, second) {
      final scoreCompare = _searchMatchScore(
        first,
        query,
      ).compareTo(_searchMatchScore(second, query));
      if (scoreCompare != 0) return scoreCompare;
      return _distanceKm(
        first.location,
        _userLocation,
      ).compareTo(_distanceKm(second.location, _userLocation));
    });
    return matches.take(3).toList(growable: false);
  }

  String _storeSearchText(Store store) =>
      '${store.name} ${store.address} ${store.city} ${store.postcode} '
              '${store.district} ${store.state} ${store.type}'
          .toLowerCase();

  int _searchMatchScore(Store store, String query) {
    final name = store.name.toLowerCase();
    final area = '${store.city} ${store.postcode} ${store.state}'.toLowerCase();
    final address = store.address.toLowerCase();
    final type = store.type.toLowerCase();
    if (name.startsWith(query)) return 0;
    if (name.contains(query)) return 1;
    if (area.contains(query)) return 2;
    if (address.contains(query)) return 3;
    if (type.contains(query)) return 4;
    return 5;
  }

  IconData _storeSuggestionIcon(Store store) {
    return store.hasPriceData
        ? Icons.storefront_outlined
        : Icons.store_mall_directory_outlined;
  }

  String _storeSuggestionSubtitle(Store store) {
    if (store.locality.isNotEmpty) return store.locality;
    return store.address;
  }

  void _selectSearchSuggestion(Store store) {
    _searchController.value = TextEditingValue(
      text: store.name,
      selection: TextSelection.collapsed(offset: store.name.length),
    );
    setState(() {
      _query = store.name;
      _showMoreStores = false;
    });
  }

  Widget _buildMap(
    List<Store> stores, {
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(20, 0, 0, 8),
  }) {
    return Padding(
      padding: padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _userLocation,
                initialZoom: 13.5,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName:
                      'com.foodraccoon.foodraccoon_store_locator',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _userLocation,
                      width: 30,
                      height: 30,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                    ...stores.map(
                      (store) => Marker(
                        point: store.location,
                        width: 46,
                        height: 46,
                        child: GestureDetector(
                          onTap: () => _showStoreDetails(store),
                          child: Container(
                            decoration: BoxDecoration(
                              color: store.hasPriceData
                                  ? foodRaccoonGreen
                                  : Colors.grey[600],
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 8),
                              ],
                            ),
                            child: Icon(
                              store.hasPriceData
                                  ? Icons.storefront
                                  : Icons.store_mall_directory_outlined,
                              color: Colors.white,
                              size: 21,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 14,
              left: 14,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 8),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.near_me,
                        color: foodRaccoonBright,
                        size: 17,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        _usingDeviceLocation
                            ? 'Your live location'
                            : _locationLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoreList(List<Store> stores, PriceCatcherSnapshot snapshot) {
    final bestValue = _bestValueStore(stores, snapshot.recommendedBasketCodes);
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 20, 8),
      children: [
        if (bestValue != null) _buildBestValueBanner(bestValue, snapshot),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Row(
            children: [
              Text(
                '${stores.length} nearby stores',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                _sortLabel,
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
        ),
        if (stores.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('No stores match your search.')),
          ),
        ...stores.map(_buildStoreCard),
      ],
    );
  }

  Widget _buildBestValueBanner(Store store, PriceCatcherSnapshot snapshot) {
    final total = store.basketTotal(snapshot.recommendedBasketCodes)!;
    return Card(
      color: const Color(0xFFE1F4E9),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: foodRaccoonGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.savings_outlined, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Best value for your basket',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${store.name} • RM${total.toStringAsFixed(2)} basket total',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: foodRaccoonGreen),
          ],
        ),
      ),
    );
  }

  Widget _buildStoreCard(Store store) {
    final distance = _distanceKm(store.location, _userLocation);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showStoreDetails(store),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 47,
                      height: 47,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE4F4EC),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        store.hasPriceData
                            ? Icons.storefront_outlined
                            : Icons.store_mall_directory_outlined,
                        color: store.hasPriceData
                            ? foodRaccoonGreen
                            : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            store.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${store.type} • ${store.address}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.circle,
                                size: 8,
                                color: store.isOpenNow
                                    ? foodRaccoonBright
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                store.currentStatus,
                                style: TextStyle(
                                  color: store.isOpenNow
                                      ? foodRaccoonBright
                                      : Colors.grey[700],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${distance.toStringAsFixed(1)} km',
                          style: const TextStyle(
                            color: foodRaccoonBright,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Icon(
                          Icons.chevron_right,
                          color: foodRaccoonGreen,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildPriceSummary(store)),
                    TextButton.icon(
                      onPressed: () => _showStoreDetails(store),
                      icon: const Icon(Icons.receipt_long_outlined, size: 16),
                      label: const Text('View prices'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        minimumSize: const Size(0, 36),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Get directions',
                      onPressed: () => _openRoute(store),
                      icon: const Icon(Icons.directions_outlined),
                      color: foodRaccoonGreen,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriceSummary(Store store) {
    if (!store.hasPriceData) {
      return Text(
        'No recent price data',
        style: TextStyle(
          color: Colors.grey[700],
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    final lowestPrice = store.lowestPrice;
    final lowestLabel = lowestPrice == null
        ? ''
        : ' • from RM${lowestPrice.toStringAsFixed(2)}';
    return Text(
      '${store.productCount} products$lowestLabel',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: foodRaccoonGreen,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  bool _matchesStoreType(Store store) {
    if (_selectedType == 'All') return true;
    final type = store.type.toLowerCase();
    switch (_selectedType) {
      case 'Supermarket':
        return type.contains('supermarket');
      case 'Hypermarket':
        return type.contains('hypermarket');
      case 'Fresh Market':
        return type == 'pasar basah';
      case 'Grocery Shop':
        return type == 'kedai runcit';
      case 'Mini Market':
        return type == 'pasar mini';
      default:
        return true;
    }
  }

  List<Store> _filteredStores(List<Store> stores) {
    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = stores.where((store) {
      final matchesType = _matchesStoreType(store);
      final matchesOpenNow = !_openNowOnly || store.isOpenNow;
      final matchesPriceData = !_hasPriceDataOnly || store.hasPriceData;
      final searchText =
          '${store.name} ${store.address} ${store.city} ${store.postcode} '
                  '${store.district} ${store.state} ${store.type}'
              .toLowerCase();
      return matchesType &&
          matchesOpenNow &&
          matchesPriceData &&
          (normalizedQuery.isEmpty || searchText.contains(normalizedQuery));
    }).toList();
    switch (_sortOption) {
      case _StoreSortOption.nearest:
        filtered.sort(
          (a, b) => _distanceKm(
            a.location,
            _userLocation,
          ).compareTo(_distanceKm(b.location, _userLocation)),
        );
      case _StoreSortOption.name:
        filtered.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case _StoreSortOption.mostPriceData:
        filtered.sort((a, b) {
          final productCompare = b.productCount.compareTo(a.productCount);
          if (productCompare != 0) return productCompare;
          return _distanceKm(
            a.location,
            _userLocation,
          ).compareTo(_distanceKm(b.location, _userLocation));
        });
    }
    return filtered;
  }

  String get _sortLabel {
    switch (_sortOption) {
      case _StoreSortOption.nearest:
        return 'Nearest first';
      case _StoreSortOption.name:
        return 'Name A–Z';
      case _StoreSortOption.mostPriceData:
        return 'Most price data';
    }
  }

  Future<void> _openFilterSheet() async {
    final selection = await showModalBottomSheet<_FilterSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StoreFilterSheet(
        initialSort: _sortOption,
        initialStoreType: _selectedType,
        initialOpenNowOnly: _openNowOnly,
        initialHasPriceDataOnly: _hasPriceDataOnly,
      ),
    );
    if (!mounted || selection == null) return;
    setState(() {
      _sortOption = selection.sortOption;
      _selectedType = selection.storeType;
      _openNowOnly = selection.openNowOnly;
      _hasPriceDataOnly = selection.hasPriceDataOnly;
      _showMoreStores = false;
    });
  }

  Store? _bestValueStore(List<Store> stores, List<int> basketCodes) {
    final eligible = stores
        .where((store) => store.basketTotal(basketCodes) != null)
        .toList();
    if (eligible.isEmpty) return null;
    eligible.sort(
      (a, b) =>
          a.basketTotal(basketCodes)!.compareTo(b.basketTotal(basketCodes)!),
    );
    return eligible.first;
  }

  double _distanceKm(LatLng a, LatLng b) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLng = _toRadians(b.longitude - a.longitude);
    final lat1 = _toRadians(a.latitude);
    final lat2 = _toRadians(b.latitude);
    final haversine =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLng / 2) *
            math.sin(dLng / 2) *
            math.cos(lat1) *
            math.cos(lat2);
    return earthRadiusKm *
        2 *
        math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  }

  double _toRadians(double value) => value * math.pi / 180;

  Future<void> _openLocationPicker() async {
    final selection = await showModalBottomSheet<_LocationSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LocationPickerSheet(
        initialLabel: _locationLabel,
        initialLocation: _userLocation,
        getDeviceLocation: _locationService.getCurrentLocation,
        locationAreas: _locationAreas,
      ),
    );
    if (!mounted || selection == null) return;

    setState(() {
      _userLocation = selection.location;
      _locationLabel = selection.label;
      _usingDeviceLocation = selection.usingDeviceLocation;
      _showMoreStores = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.move(selection.location, 13.5);
      } catch (_) {}
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Searching near ${selection.label}.')),
    );
  }

  void _showStoreDetails(Store store) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StoreDetailsSheet(
        store: store,
        distanceKm: _distanceKm(store.location, _userLocation),
        onOpenRoute: () => _openRoute(store),
      ),
    );
  }

  Future<void> _openRoute(Store store) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&origin=${_userLocation.latitude},${_userLocation.longitude}&destination=${store.latitude},${store.longitude}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the route.')),
      );
    }
  }
}

class _FilterSelection {
  const _FilterSelection({
    required this.sortOption,
    required this.storeType,
    required this.openNowOnly,
    required this.hasPriceDataOnly,
  });

  final _StoreSortOption sortOption;
  final String storeType;
  final bool openNowOnly;
  final bool hasPriceDataOnly;
}

class _StoreFilterSheet extends StatefulWidget {
  const _StoreFilterSheet({
    required this.initialSort,
    required this.initialStoreType,
    required this.initialOpenNowOnly,
    required this.initialHasPriceDataOnly,
  });

  final _StoreSortOption initialSort;
  final String initialStoreType;
  final bool initialOpenNowOnly;
  final bool initialHasPriceDataOnly;

  @override
  State<_StoreFilterSheet> createState() => _StoreFilterSheetState();
}

class _StoreFilterSheetState extends State<_StoreFilterSheet> {
  late _StoreSortOption _sortOption = widget.initialSort;
  late String _storeType = widget.initialStoreType;
  late bool _openNowOnly = widget.initialOpenNowOnly;
  late bool _hasPriceDataOnly = widget.initialHasPriceDataOnly;

  static const _storeTypes = [
    'All',
    'Supermarket',
    'Hypermarket',
    'Fresh Market',
    'Grocery Shop',
    'Mini Market',
  ];

  String _sortLabel(_StoreSortOption option) {
    switch (option) {
      case _StoreSortOption.nearest:
        return 'Nearest first';
      case _StoreSortOption.name:
        return 'Name A–Z';
      case _StoreSortOption.mostPriceData:
        return 'Most price data';
    }
  }

  void _clear() {
    setState(() {
      _sortOption = _StoreSortOption.nearest;
      _storeType = 'All';
      _openNowOnly = false;
      _hasPriceDataOnly = false;
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      _FilterSelection(
        sortOption: _sortOption,
        storeType: _storeType,
        openNowOnly: _openNowOnly,
        hasPriceDataOnly: _hasPriceDataOnly,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.min(650, MediaQuery.sizeOf(context).height * 0.85),
        ),
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCE9E2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Filter and sort',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Sort by',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _StoreSortOption.values
                        .map(
                          (option) => ChoiceChip(
                            label: Text(_sortLabel(option)),
                            selected: _sortOption == option,
                            selectedColor: const Color(0xFFD9F2E6),
                            checkmarkColor: foodRaccoonGreen,
                            side: BorderSide(
                              color: _sortOption == option
                                  ? foodRaccoonBright
                                  : const Color(0xFFDCE9E2),
                            ),
                            onSelected: (_) =>
                                setState(() => _sortOption = option),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Store type',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _storeTypes
                        .map(
                          (type) => ChoiceChip(
                            label: Text(type),
                            selected: _storeType == type,
                            selectedColor: const Color(0xFFD9F2E6),
                            checkmarkColor: foodRaccoonGreen,
                            side: BorderSide(
                              color: _storeType == type
                                  ? foodRaccoonBright
                                  : const Color(0xFFDCE9E2),
                            ),
                            onSelected: (_) =>
                                setState(() => _storeType = type),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Filters',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Open now'),
                    subtitle: const Text('Only show stores marked open'),
                    value: _openNowOnly,
                    activeThumbColor: foodRaccoonGreen,
                    onChanged: (value) => setState(() => _openNowOnly = value),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Has price data'),
                    subtitle: const Text('Hide stores without recent prices'),
                    value: _hasPriceDataOnly,
                    activeThumbColor: foodRaccoonGreen,
                    onChanged: (value) =>
                        setState(() => _hasPriceDataOnly = value),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton(onPressed: _clear, child: const Text('Clear')),
                      const Spacer(),
                      FilledButton(
                        onPressed: _apply,
                        style: FilledButton.styleFrom(
                          backgroundColor: foodRaccoonGreen,
                        ),
                        child: const Text('Apply filters'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LocationSelection {
  const _LocationSelection({
    required this.location,
    required this.label,
    required this.usingDeviceLocation,
  });

  final LatLng location;
  final String label;
  final bool usingDeviceLocation;
}

class _LocationSuggestion {
  const _LocationSuggestion({
    required this.title,
    required this.subtitle,
    required this.location,
  });

  final String title;
  final String subtitle;
  final LatLng location;

  String get label => subtitle.isEmpty ? title : '$title, $subtitle';
}

class _LocationPreset {
  const _LocationPreset({
    required this.label,
    required this.matchText,
    required this.location,
  });

  final String label;
  final String matchText;
  final LatLng location;
}

class _LocationPickerSheet extends StatefulWidget {
  const _LocationPickerSheet({
    required this.initialLabel,
    required this.initialLocation,
    required this.getDeviceLocation,
    required this.locationAreas,
  });

  final String initialLabel;
  final LatLng initialLocation;
  final Future<LatLng?> Function() getDeviceLocation;
  final List<LocationArea> locationAreas;

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  static const _presets = [
    _LocationPreset(
      label: 'TAR UMT, Setapak',
      matchText: 'setapak',
      location: LatLng(3.2090, 101.7250),
    ),
    _LocationPreset(
      label: 'Wangsa Maju, Kuala Lumpur',
      matchText: 'wangsa',
      location: LatLng(3.2050, 101.7250),
    ),
    _LocationPreset(
      label: 'Setiawangsa, Kuala Lumpur',
      matchText: 'setiawangsa',
      location: LatLng(3.1900, 101.7350),
    ),
    _LocationPreset(
      label: 'Titiwangsa, Kuala Lumpur',
      matchText: 'titiwangsa',
      location: LatLng(3.1850, 101.7100),
    ),
    _LocationPreset(
      label: 'KLCC, Kuala Lumpur',
      matchText: 'klcc',
      location: LatLng(3.1579, 101.7116),
    ),
  ];

  final _placeController = TextEditingController();
  final _pickerMapController = MapController();
  List<_LocationSuggestion> _suggestions = const [];
  _LocationSuggestion? _selectedSuggestion;
  late LatLng _selectedLocation;
  LatLng? _droppedPin;
  bool _settingPlaceText = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
    _placeController.text = widget.initialLabel == 'TAR UMT, Setapak'
        ? ''
        : widget.initialLabel;
  }

  @override
  void dispose() {
    _placeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Choose your location',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Text(
                'Use GPS or choose a place to search around another area.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              const SizedBox(height: 15),
              SizedBox(
                height: 176,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _pickerMapController,
                        options: MapOptions(
                          initialCenter: _selectedLocation,
                          initialZoom: 13.5,
                          onTap: (_, point) => _dropMapPin(point),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName:
                                'com.foodraccoon.foodraccoon_store_locator',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _selectedLocation,
                                width: 42,
                                height: 42,
                                child: const Icon(
                                  Icons.location_pin,
                                  color: Colors.red,
                                  size: 42,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: Text(
                              _droppedPin == null
                                  ? 'Tap map to drop a pin'
                                  : 'Pin selected • Use this place',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading ? null : _useDeviceLocation,
                icon: const Icon(Icons.my_location_outlined),
                label: const Text('Use my device location'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _placeController,
                onChanged: _onPlaceChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _usePlace(),
                decoration: InputDecoration(
                  labelText: 'Enter a place or address',
                  hintText: 'Example: KLCC, Kuala Lumpur',
                  prefixIcon: const Icon(Icons.search),
                  errorText: _error,
                ),
              ),
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildSuggestionList(),
              ] else if (_shouldShowNoMatchMessage) ...[
                const SizedBox(height: 8),
                Text(
                  'No location suggestion. You can still use this address.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Quick locations',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: _presets
                    .map(
                      (preset) => ActionChip(
                        label: Text(preset.label),
                        onPressed: () => _selectQuickLocation(preset),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _loading
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _loading ? null : _usePlace,
                      child: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Use this place'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _dropMapPin(LatLng point) {
    _settingPlaceText = true;
    _placeController.clear();
    _settingPlaceText = false;
    setState(() {
      _selectedLocation = point;
      _droppedPin = point;
      _selectedSuggestion = null;
      _suggestions = const [];
      _error = null;
    });
  }

  void _selectQuickLocation(_LocationPreset preset) {
    _selectedLocation = preset.location;
    _droppedPin = null;
    _selectedSuggestion = null;
    _placeController.text = preset.label;
    setState(() {
      _suggestions = const [];
      _error = null;
    });
    _movePickerMap(preset.location);
  }

  void _movePickerMap(LatLng location) {
    try {
      _pickerMapController.move(location, 13.5);
    } catch (_) {}
  }

  bool get _shouldShowNoMatchMessage =>
      !_loading &&
      _selectedSuggestion == null &&
      _placeController.text.trim().length >= 2 &&
      _suggestions.isEmpty;

  void _onPlaceChanged(String value) {
    if (_settingPlaceText) return;
    final query = value.trim().toLowerCase();
    if (_selectedSuggestion != null &&
        _selectedSuggestion!.title.toLowerCase() == query) {
      return;
    }

    _droppedPin = null;
    _selectedSuggestion = null;
    if (query.length < 2) {
      setState(() {
        _suggestions = const [];
        _error = null;
      });
      return;
    }

    final matches = <_LocationSuggestion>[];
    final seenLabels = <String>{};
    for (final area in widget.locationAreas) {
      final searchableText = '${area.city} ${area.state} ${area.postcode}'
          .toLowerCase();
      if (searchableText.contains(query) &&
          seenLabels.add(area.label.toLowerCase())) {
        matches.add(
          _LocationSuggestion(
            title: area.label,
            subtitle: area.subtitle,
            location: area.location,
          ),
        );
      }
    }
    for (final preset in _presets) {
      final searchableText = '${preset.label} ${preset.matchText}'
          .toLowerCase();
      if (searchableText.contains(query) &&
          seenLabels.add(preset.label.toLowerCase())) {
        matches.add(
          _LocationSuggestion(
            title: preset.label,
            subtitle: '',
            location: preset.location,
          ),
        );
      }
    }
    matches.sort((first, second) {
      final firstStarts = first.title.toLowerCase().startsWith(query);
      final secondStarts = second.title.toLowerCase().startsWith(query);
      if (firstStarts != secondStarts) return firstStarts ? -1 : 1;
      return first.title.compareTo(second.title);
    });

    setState(() {
      _suggestions = matches.take(5).toList(growable: false);
      _error = null;
    });
  }

  Widget _buildSuggestionList() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE9E2)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < _suggestions.length; index++) ...[
            InkWell(
              onTap: () => _selectSuggestion(_suggestions[index]),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: foodRaccoonBright,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _suggestions[index].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _suggestions[index].subtitle.isEmpty
                                ? 'Location area'
                                : _suggestions[index].subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.north_west, size: 16),
                  ],
                ),
              ),
            ),
            if (index != _suggestions.length - 1)
              const Divider(height: 1, indent: 42, endIndent: 12),
          ],
        ],
      ),
    );
  }

  void _selectSuggestion(_LocationSuggestion suggestion) {
    _selectedLocation = suggestion.location;
    _droppedPin = null;
    _selectedSuggestion = suggestion;
    _placeController.text = suggestion.title;
    setState(() {
      _suggestions = const [];
      _error = null;
    });
    _movePickerMap(suggestion.location);
  }

  Future<void> _useDeviceLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final location = await widget.getDeviceLocation();
    if (!mounted) return;
    if (location == null) {
      setState(() {
        _loading = false;
        _error = 'GPS unavailable. Enter a place manually instead.';
      });
      return;
    }
    Navigator.of(context).pop(
      _LocationSelection(
        location: location,
        label: 'Your live location',
        usingDeviceLocation: true,
      ),
    );
  }

  Future<void> _usePlace() async {
    final query = _placeController.text.trim();
    if (_droppedPin != null) {
      Navigator.of(context).pop(
        _LocationSelection(
          location: _droppedPin!,
          label: 'Pinned map location',
          usingDeviceLocation: false,
        ),
      );
      return;
    }
    if (query.isEmpty) {
      Navigator.of(context).pop(
        _LocationSelection(
          location: _selectedLocation,
          label: widget.initialLabel,
          usingDeviceLocation: false,
        ),
      );
      return;
    }

    final normalizedQuery = query.toLowerCase();
    if (_selectedSuggestion != null &&
        _selectedSuggestion!.title.toLowerCase() == normalizedQuery) {
      Navigator.of(context).pop(
        _LocationSelection(
          location: _selectedSuggestion!.location,
          label: _selectedSuggestion!.title,
          usingDeviceLocation: false,
        ),
      );
      return;
    }

    if (_suggestions.length == 1 &&
        _suggestions.first.title.toLowerCase().startsWith(normalizedQuery)) {
      Navigator.of(context).pop(
        _LocationSelection(
          location: _suggestions.first.location,
          label: _suggestions.first.title,
          usingDeviceLocation: false,
        ),
      );
      return;
    }

    for (final preset in _presets) {
      if (normalizedQuery.contains(preset.matchText)) {
        Navigator.of(context).pop(
          _LocationSelection(
            location: preset.location,
            label: preset.label,
            usingDeviceLocation: false,
          ),
        );
        return;
      }
    }

    if (kIsWeb) {
      setState(
        () => _error =
            'Choose a suggested area, drop a pin, or use Android for full address lookup.',
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final geocoding = Geocoding();
      final locations = await geocoding.locationFromAddress(query);
      if (!mounted) return;
      if (locations.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Place not found. Try a fuller address.';
        });
        return;
      }
      final location = locations.first;
      Navigator.of(context).pop(
        _LocationSelection(
          location: LatLng(location.latitude, location.longitude),
          label: query,
          usingDeviceLocation: false,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Address lookup failed. Try a quick location instead.';
      });
    }
  }
}

class StoreDetailsSheet extends StatelessWidget {
  const StoreDetailsSheet({
    required this.store,
    required this.distanceKm,
    required this.onOpenRoute,
    super.key,
  });

  final Store store;
  final double distanceKm;
  final VoidCallback onOpenRoute;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCE9E2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      store.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                store.type,
                style: const TextStyle(
                  color: foodRaccoonBright,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                store.address,
                style: TextStyle(color: Colors.grey[700], height: 1.4),
              ),
              if (store.locality.isNotEmpty) ...[
                const SizedBox(height: 5),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.location_city_outlined,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        store.locality,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      store.coordinateSource == 'postcode centroid'
                          ? 'Approximate location • based on postcode'
                          : 'Approximate location • based on state area',
                      style: TextStyle(color: Colors.grey[600], fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _DetailMetric(
                        icon: Icons.near_me_outlined,
                        label: 'Distance',
                        value: '${distanceKm.toStringAsFixed(1)} km',
                        onTap: onOpenRoute,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DetailMetric(
                        icon: Icons.schedule_outlined,
                        label: 'Opening hours',
                        value: store.openingHours,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Price information',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (!store.hasPriceData)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F5F4),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'No recent PriceCatcher records are available for this store. You can still use the address and route.',
                    style: TextStyle(height: 1.35),
                  ),
                ),
              if (store.hasPriceData) ...[
                Text(
                  '${store.productCount} products recorded • latest ${store.latestPriceDate}',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                ),
                const SizedBox(height: 4),
                ...store.products.map(
                  (product) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE4F4EC),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.shopping_basket_outlined,
                        size: 19,
                        color: foodRaccoonGreen,
                      ),
                    ),
                    title: Text(
                      product.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text('${product.unit} • ${product.date}'),
                    trailing: Text(
                      'RM${product.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: foodRaccoonGreen,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onOpenRoute,
                  icon: const Icon(Icons.directions_outlined),
                  label: const Text('Open route'),
                  style: FilledButton.styleFrom(
                    backgroundColor: foodRaccoonGreen,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEAF6EF),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, size: 18, color: foodRaccoonBright),
                  if (onTap != null)
                    const Icon(
                      Icons.directions_outlined,
                      size: 17,
                      color: foodRaccoonBright,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: foodRaccoonGreen,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(height: 3),
                Text(
                  'Tap to open route',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 44,
              color: foodRaccoonGreen,
            ),
            const SizedBox(height: 12),
            const Text(
              'Store data could not be loaded',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text('Please try again.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
