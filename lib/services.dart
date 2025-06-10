// lib/services.dart
import 'package:cloud_firestore/cloud_firestore.dart'
    show
        FirebaseFirestore,
        FieldValue,
        GeoPoint,
        DocumentSnapshot,
        DocumentReference,
        QuerySnapshot;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Bu dosya aslında kullanılmıyor, kaldırılabilir
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
    String source = "Unknown",
  }) async {
    try {
      DocumentReference docRef =
          await _firestore.collection('emergency_locations').add({
        'location': GeoPoint(latitude, longitude),
        'timestamp': FieldValue.serverTimestamp(),
        'esp32_nearest_area_name': esp32NearestAreaName,
        'esp32_distance_to_area_m': esp32DistanceToAreaM,
        'esp32_direction_to_area': esp32DirectionToArea,
        'esp32_satellites': esp32Satellites,
        'source': source,
      });
      if (kDebugMode)
        print('Acil durum konumu Firestore\'a kaydedildi: ${docRef.id}');
      return await docRef.get();
    } catch (e) {
      if (kDebugMode) print('Acil durum konumunu kaydederken hata oluştu: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> findNearestRendezvousArea(
      double currentLatitude, double currentLongitude) async {
    try {
      // 'area' koleksiyonundaki 'areas' belgesini al
      DocumentSnapshot areaDoc =
          await _firestore.collection('area').doc('areas').get();

      if (!areaDoc.exists) {
        throw 'Firestore\'da "area" koleksiyonu altında "areas" belgesi bulunamadı.';
      }

      // data() metodu null dönebilir, bu yüzden kontrol etmek önemlidir.
      // Ayrıca, döndüğü Map'in doğru türde olduğundan emin olmak için açıkça dönüştürüyoruz.
      Map<String, dynamic>? data = areaDoc.data() as Map<String, dynamic>?;

      if (data == null || !data.containsKey('areasarray')) {
        throw 'Firestore\'daki "areas" belgesinde "areasarray" alanı bulunamadı veya hatalı formatta.';
      }

      // areasarray alanına doğrudan erişim
      List<dynamic> rawAreas = data['areasarray'];
      List<GeoPoint> areasList = [];

      // Raw veriyi GeoPoint listesine dönüştürürken null ve hatalı formatları yönet
      for (var item in rawAreas) {
        if (item is GeoPoint) {
          areasList.add(item);
        } else if (item is Map &&
            item.containsKey('_latitude') &&
            item.containsKey('_longitude')) {
          // Firebase'in bazı sürümlerinde GeoPoint'ler Map olarak dönebilir.
          // Enlem ve boylam değerlerinin null olmadığından emin ol.
          double? lat = item['_latitude'] as double?;
          double? lon = item['_longitude'] as double?;

          if (lat != null && lon != null) {
            areasList.add(GeoPoint(lat, lon));
          } else {
            if (kDebugMode)
              print(
                  "Hata: Map'ten GeoPoint oluşturulurken enlem/boylam null veya hatalı: $item");
            // Bu hatalı girişi atla, uygulamayı çökertme
          }
        } else {
          if (kDebugMode)
            print("Geçersiz GeoPoint formatı algılandı ve atlandı: $item");
        }
      }

      if (areasList.isEmpty) {
        throw 'Firestore\'dan geçerli toplanma alanı koordinatları alınamadı.';
      }

      double minDistance = double.infinity;
      Map<String, dynamic> nearestAreaInfo = {};
      int nearestAreaIndex = -1; // En yakın alanın indeksi

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
          nearestAreaIndex = i;
          nearestAreaInfo = {
            'coordinates': GeoPoint(geoPoint.latitude, geoPoint.longitude),
            'distance_km': (minDistance / 1000).toStringAsFixed(2),
            'distance_m': minDistance.toStringAsFixed(1),
          };
        }
      }

      if (nearestAreaInfo.isEmpty) {
        throw 'En yakın toplanma alanı hesaplanamadı.';
      }

      // Alanın adını indeksine göre belirle (eğer Firestore'da isim yoksa)
      nearestAreaInfo['name'] =
          'Area ${nearestAreaIndex + 1}'; // 1'den başlayarak isimlendir

      if (kDebugMode) {
        print(
            'En yakın toplanma alanı bulundu: ${nearestAreaInfo['name']}, Koordinatlar: ${nearestAreaInfo['coordinates']}, Uzaklık: ${nearestAreaInfo['distance_km']} km');
      }
      return nearestAreaInfo;
    } catch (e) {
      if (kDebugMode) {
        print('En yakın toplanma alanı bulma hatası: $e');
      }
      rethrow;
    }
  }
}
