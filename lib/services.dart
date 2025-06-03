import 'package:cloud_firestore/cloud_firestore.dart'
    show
        FirebaseFirestore,
        FieldValue,
        GeoPoint,
        DocumentSnapshot,
        DocumentReference;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    String? esp32DirectionToArea,
    int? esp32Satellites,
    String source = "ESP32", // "ESP32" veya "Mobile"
  }) async {
    try {
      final docRef = await _firestore.collection('emergencies').add({
        'location': GeoPoint(latitude, longitude),
        'timestamp': FieldValue.serverTimestamp(),
        'source': source,
        'esp32_nearest_area_name': esp32NearestAreaName,
        'esp32_distance_to_area_m': esp32DistanceToAreaM,
        'esp32_direction_to_area': esp32DirectionToArea,
        'esp32_satellites': esp32Satellites,
      });

      // Kaydedilen belgeyi geri döndür
      return await docRef.get();
    } catch (e) {
      if (kDebugMode) print("Acil durum konumu kaydetme hatası: $e");
      rethrow;
    }
  }

  Future<Map<String, dynamic>> findNearestRendezvousArea(
      double currentLatitude, double currentLongitude) async {
    try {
      final querySnapshot =
          await _firestore.collection('rendezvous_points').get();

      if (querySnapshot.docs.isEmpty) {
        throw 'Firestore\'da tanımlı toplanma alanı bulunamadı.';
      }

      List<GeoPoint> areasList = [];
      for (var doc in querySnapshot.docs) {
        if (doc.data().containsKey('location') &&
            doc.data()['location'] is GeoPoint) {
          areasList.add(doc.data()['location'] as GeoPoint);
        } else if (doc.data().containsKey('coordinates') &&
            doc.data()['coordinates'] is GeoPoint) {
          // 'coordinates' olarak da tanımlanmış olabilir
          areasList.add(doc.data()['coordinates'] as GeoPoint);
        } else {
          // Eğer geopoint değilse, manuel olarak GeoPoint'e çevirmeye çalış
          var item = doc.data()['location'];
          if (item != null &&
              item is Map &&
              item.containsKey('latitude') &&
              item.containsKey('longitude')) {
            try {
              areasList.add(GeoPoint(item['latitude'], item['longitude']));
            } catch (e) {
              if (kDebugMode)
                print("Geopoint'e dönüştürme hatası: $item, Hata: $e");
            }
          }
        }
      }

      if (areasList.isEmpty) {
        throw 'Geçerli formatta toplanma alanı bulunamadı. Lütfen Firestore\'daki veriyi kontrol edin.';
      }

      double minDistance = double.infinity;
      Map<String, dynamic> nearestAreaInfo = {};

      for (GeoPoint geoPoint in areasList) {
        double distanceInMeters = Geolocator.distanceBetween(
          currentLatitude,
          currentLongitude,
          geoPoint.latitude,
          geoPoint.longitude,
        );

        if (distanceInMeters < minDistance) {
          minDistance = distanceInMeters;
          // Firestore belgesinden ismi almayı dene
          String? areaName;
          try {
            var doc = querySnapshot.docs.firstWhere((d) =>
                (d.data().containsKey('location') &&
                    d.data()['location'] == geoPoint) ||
                (d.data().containsKey('coordinates') &&
                    d.data()['coordinates'] == geoPoint));
            areaName = doc.data().containsKey('name')
                ? doc.data()['name'] as String?
                : null;
          } catch (e) {
            // Eğer eşleşen belge bulunamazsa veya isim alanı yoksa
            areaName = 'Bilinmeyen Alan';
          }

          nearestAreaInfo = {
            'name': areaName,
            'coordinates': GeoPoint(geoPoint.latitude, geoPoint.longitude),
            'distance_km': (distanceInMeters / 1000).toStringAsFixed(2),
            'distance_m': distanceInMeters.toStringAsFixed(1),
          };
        }
      }

      if (nearestAreaInfo.isEmpty) {
        throw 'En yakın toplanma alanı hesaplanamadı (muhtemelen hiç alan bulunamadı).';
      }

      if (kDebugMode) {
        print(
            'En yakın toplanma alanı bulundu: ${nearestAreaInfo['coordinates']}, Uzaklık: ${nearestAreaInfo['distance_km']} km');
      }
      return nearestAreaInfo;
    } catch (e) {
      if (kDebugMode) {
        print("En yakın toplanma alanı bulunurken hata oluştu: $e");
      }
      rethrow;
    }
  }
}
