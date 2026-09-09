import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/location.dart';
import '../../providers/trip_providers.dart';
import '../../services/map/map_provider.dart';

/// 选地点：关键词搜索 + 直接在地图上点。
///
/// 没配服务商密钥时搜索不可用，但仍可点图选点并手填名称 ——
/// 只要有坐标，路线图和通勤估算就都能工作。
class PlacePickerScreen extends ConsumerStatefulWidget {
  const PlacePickerScreen({super.key, required this.tripId, this.initial});

  final String tripId;
  final GeoPlace? initial;

  @override
  ConsumerState<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends ConsumerState<PlacePickerScreen> {
  final _searchController = TextEditingController();
  final _mapController = MapController();

  Timer? _debounce;
  List<GeoPlace> _results = const [];
  bool _searching = false;
  GeoPlace? _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial;
    _searchController.text = widget.initial?.name ?? '';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providerAsync = ref.watch(tripMapProviderProvider(widget.tripId));
    final provider = providerAsync.valueOrNull ?? const OsmProvider();
    final adapter = MapDisplayAdapter(provider.tileSource.datum);
    final center = _picked?.latLng ?? const LatLng(35.0116, 135.7681); // 兜底：京都

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择地点'),
        actions: [
          TextButton(
            onPressed: _picked == null ? null : () => Navigator.pop(context, _picked),
            child: const Text('使用'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: provider.isConfigured
                    ? '搜索地点，或直接在地图上长按选点'
                    : '未配置${provider.displayName}密钥，请长按地图选点',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          if (_results.isNotEmpty)
            SizedBox(
              height: 180,
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final place = _results[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.place_outlined, size: 20),
                    title: Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: place.address == null
                        ? null
                        : Text(place.address!, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => _select(place, adapter),
                  );
                },
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: adapter.toDisplay(center),
                    initialZoom: 13,
                    // 长按而不是单击：单击容易在拖地图时误触。
                    onLongPress: (_, displayed) => _pickFromMap(displayed, adapter, provider),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: provider.tileSource.urlTemplate,
                      subdomains: provider.tileSource.subdomains,
                      maxZoom: provider.tileSource.maxZoom,
                      userAgentPackageName: 'io.github.kinnuch.itinera',
                    ),
                    if (_picked?.latLng != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: adapter.toDisplay(_picked!.latLng!),
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.location_on,
                              size: 40,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _PickedCard(place: _picked, attribution: provider.tileSource.attribution),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    // 输入防抖：每敲一个字都发请求会很快烧掉服务商配额。
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value.trim()));
  }

  Future<void> _search(String keyword) async {
    final provider = ref.read(tripMapProviderProvider(widget.tripId)).valueOrNull;
    if (provider == null || !provider.isConfigured) return;

    setState(() => _searching = true);
    try {
      final near = _picked?.latLng ?? _mapController.camera.center;
      final results = await provider.searchPlaces(keyword, near: near);
      if (mounted) setState(() => _results = results);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _select(GeoPlace place, MapDisplayAdapter adapter) {
    setState(() {
      _picked = place;
      _results = const [];
      _searchController.text = place.name;
    });
    final point = place.latLng;
    if (point != null) {
      _mapController.move(adapter.toDisplay(point), 15);
    }
  }

  /// 地图返回的是「显示坐标系」的点，入库前要搬回 WGS-84。
  Future<void> _pickFromMap(
    LatLng displayed,
    MapDisplayAdapter adapter,
    MapProvider provider,
  ) async {
    final stored = adapter.toStored(displayed);
    setState(() {
      _picked = GeoPlace(
        name: _searchController.text.trim().isEmpty
            ? '地图选点'
            : _searchController.text.trim(),
        latitude: stored.latitude,
        longitude: stored.longitude,
        provider: provider.id,
      );
    });
    // 有密钥时顺手反查地址，把名字换成人能看懂的。
    final resolved = await provider.reverseGeocode(stored);
    if (resolved != null && mounted) {
      setState(() {
        _picked = _picked!.copyWith(
          name: _searchController.text.trim().isEmpty ? resolved.name : _picked!.name,
          address: resolved.address,
        );
      });
    }
  }
}

class _PickedCard extends StatelessWidget {
  const _PickedCard({required this.place, required this.attribution});

  final GeoPlace? place;
  final String attribution;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surface.withValues(alpha: 0.95),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              place?.name ?? '长按地图选择位置',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (place?.address != null)
              Text(
                place!.address!,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            Text(attribution, style: TextStyle(fontSize: 10, color: scheme.outline)),
          ],
        ),
      ),
    );
  }
}
