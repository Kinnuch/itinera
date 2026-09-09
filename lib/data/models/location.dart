import 'package:latlong2/latlong.dart';

/// 一个地点。坐标统一以 WGS-84 存储；[providerPoiId] 保留服务商 POI id 便于二次查询。
class GeoPlace {
  const GeoPlace({
    required this.name,
    this.address,
    this.latitude,
    this.longitude,
    this.providerPoiId,
    this.provider,
  });

  final String name;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? providerPoiId;
  final String? provider;

  bool get hasCoordinates => latitude != null && longitude != null;

  LatLng? get latLng => hasCoordinates ? LatLng(latitude!, longitude!) : null;

  GeoPlace copyWith({
    String? name,
    String? address,
    double? latitude,
    double? longitude,
    String? providerPoiId,
    String? provider,
  }) {
    return GeoPlace(
      name: name ?? this.name,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      providerPoiId: providerPoiId ?? this.providerPoiId,
      provider: provider ?? this.provider,
    );
  }

  Map<String, Object?> toMap(String prefix) => {
        '${prefix}_name': name,
        '${prefix}_address': address,
        '${prefix}_lat': latitude,
        '${prefix}_lng': longitude,
        '${prefix}_poi_id': providerPoiId,
        '${prefix}_provider': provider,
      };

  static GeoPlace? fromMap(Map<String, Object?> row, String prefix) {
    final name = row['${prefix}_name'] as String?;
    if (name == null || name.isEmpty) return null;
    return GeoPlace(
      name: name,
      address: row['${prefix}_address'] as String?,
      latitude: (row['${prefix}_lat'] as num?)?.toDouble(),
      longitude: (row['${prefix}_lng'] as num?)?.toDouble(),
      providerPoiId: row['${prefix}_poi_id'] as String?,
      provider: row['${prefix}_provider'] as String?,
    );
  }

  @override
  String toString() => address == null ? name : '$name · $address';
}
