import 'package:cloud_firestore/cloud_firestore.dart'
    show
        FirebaseFirestore,
        FieldValue,
        GeoPoint,
        DocumentSnapshot,
        DocumentReference;
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class EmergencyServices {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Position> getMobileDeviceCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw 'Konum servisleri kapalı. Lütfen aktif edin.';
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw 'Konum izni reddedildi.';
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw 'Konum izni kalıcı olarak reddedildi. Ayarlardan izin vermeniz gerekir.';
    }
    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }

  Future<DocumentSnapshot> saveEmergencyLocation({
    required double latitude,
    required double longitude,
    String? esp32NearestAreaName,
    double? esp32DistanceToAreaM,
    String?
        esp32DirectionToArea, // DEĞİŞTİ: Artık hesaplanan yön buraya gelecek
    int? esp32Satellites,
    String source = "Unknown",
  }) async {
    try {
      DocumentReference docRef =
          await _firestore.collection('emergency_locations').add({
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'esp32_nearest_area_name': esp32NearestAreaName,
        'esp32_distance_to_area_m': esp32DistanceToAreaM,
        'esp32_direction_to_area': esp32DirectionToArea,
        'esp32_satellites': esp32Satellites,
        'source': source,
      });
      if (kDebugMode) {
        print('Acil durum konumu Firestore\'a kaydedildi: ${docRef.id}');
      }
      return await docRef.get();
    } catch (e) {
      if (kDebugMode) print('Acil durum konumunu kaydederken hata oluştu: $e');
      rethrow;
    }
  }

  // YENİ: Dereceyi yön kısaltmasına çeviren yardımcı fonksiyon
  String getDirectionAbbreviation(double bearing) {
    if (bearing < 0) bearing += 360; // Negatif dereceleri pozitife çevir
    if ((bearing >= 337.5) || (bearing < 22.5)) return "K";
    if ((bearing >= 22.5) && (bearing < 67.5)) return "KD";
    if ((bearing >= 67.5) && (bearing < 112.5)) return "D";
    if ((bearing >= 112.5) && (bearing < 157.5)) return "GD";
    if ((bearing >= 157.5) && (bearing < 202.5)) return "G";
    if ((bearing >= 202.5) && (bearing < 247.5)) return "GB";
    if ((bearing >= 247.5) && (bearing < 292.5)) return "B";
    if ((bearing >= 292.5) && (bearing < 337.5)) return "KB";
    return "---";
  }

  Future<Map<String, dynamic>> findNearestRendezvousArea(
      double currentLatitude, double currentLongitude) async {
    try {
      DocumentSnapshot areaDoc =
          await _firestore.collection('area').doc('areas').get();

      if (!areaDoc.exists) {
        throw 'Firestore\'da "areas" belgesi bulunamadı.';
      }

      Map<String, dynamic>? data = areaDoc.data() as Map<String, dynamic>?;

      if (data == null || !data.containsKey('areasarray')) {
        throw 'Firestore "areas" belgesinde "areasarray" alanı yok.';
      }

      List<dynamic> rawAreas = data['areasarray'];
      List<GeoPoint> areasList = [];

      for (var item in rawAreas) {
        if (item is GeoPoint) {
          areasList.add(item);
        } else if (item is Map &&
            item.containsKey('_latitude') &&
            item.containsKey('_longitude')) {
          double? lat = item['_latitude'] as double?;
          double? lon = item['_longitude'] as double?;
          if (lat != null && lon != null) {
            areasList.add(GeoPoint(lat, lon));
          }
        }
      }

      if (areasList.isEmpty) {
        throw 'Geçerli toplanma alanı koordinatı alınamadı.';
      }

      double minDistance = double.infinity;
      GeoPoint? nearestGeoPoint;
      int nearestAreaIndex = -1;

      for (int i = 0; i < areasList.length; i++) {
        GeoPoint geoPoint = areasList[i];
        double distanceInMeters = Geolocator.distanceBetween(
          currentLatitude,
          currentLongitude,
          geoPoint.latitude,
          geoPoint.longitude,
        );

        if (distanceInMeters < minDistance) {
          minDistance = distanceInMeters;
          nearestGeoPoint = geoPoint;
          nearestAreaIndex = i;
        }
      }

      if (nearestGeoPoint == null) {
        throw 'En yakın toplanma alanı hesaplanamadı.';
      }

      // DEĞİŞTİ: Yön (bearing) hesaplaması ve metne çevirme
      double bearing = Geolocator.bearingBetween(
        currentLatitude,
        currentLongitude,
        nearestGeoPoint.latitude,
        nearestGeoPoint.longitude,
      );
      String directionAbbr = getDirectionAbbreviation(bearing);

      Map<String, dynamic> nearestAreaInfo = {
        'coordinates': nearestGeoPoint,
        'distance_km': (minDistance / 1000).toStringAsFixed(2),
        'distance_m': minDistance.toStringAsFixed(1),
        'name': 'Alan ${nearestAreaIndex + 1}',
        'bearing_deg': bearing, // ESP32'ye göndermek için derece
        'direction_abbr': directionAbbr, // Firestore'a kaydetmek için metin
      };

      if (kDebugMode) {
        print(
            'En yakın alan: ${nearestAreaInfo['name']}, Uzaklık: ${nearestAreaInfo['distance_km']} km, Yön: ${nearestAreaInfo['direction_abbr']} (${nearestAreaInfo['bearing_deg']})');
      }
      return nearestAreaInfo;
    } catch (e) {
      if (kDebugMode) print('En yakın toplanma alanı bulma hatası: $e');
      rethrow;
    }
  }
}
