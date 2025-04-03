import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class EmergencyServices {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Kullanıcının konumunu al
  Future<Position> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw 'Konum servisleri kapalı';
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw 'Konum izni reddedildi';
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw 'Konum izni kalıcı olarak reddedildi';
    }

    return await Geolocator.getCurrentPosition();
  }

  // Acil durumu Firestore'a kaydet
  Future<void> saveEmergencyLocation() async {
    try {
      Position position = await getCurrentLocation();
      await _firestore.collection('emergencies').add({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw 'Konum kaydedilemedi: $e';
    }
  }

  // En yakın toplanma alanını bul
  Future<Map<String, dynamic>> findNearestGatheringArea() async {
    try {
      Position currentPosition = await getCurrentLocation();

      // Firestore'dan toplanma alanlarını al
      QuerySnapshot areaSnapshot = await _firestore.collection('areas').get();

      double minDistance = double.infinity;
      Map<String, dynamic> nearestArea = {};

      // Her bir toplanma alanı için mesafe hesapla
      for (var doc in areaSnapshot.docs) {
        List<String> coordinates = (doc['areasarray'] as String)
            .replaceAll('[', '')
            .replaceAll(']', '')
            .split(',');

        double areaLat = double.parse(coordinates[0].trim());
        double areaLng = double.parse(coordinates[1].trim());

        double distance = Geolocator.distanceBetween(
          currentPosition.latitude,
          currentPosition.longitude,
          areaLat,
          areaLng,
        );

        if (distance < minDistance) {
          minDistance = distance;
          nearestArea = {
            'coordinates': '${areaLat}, ${areaLng}',
            'distance': (distance / 1000).toStringAsFixed(2), // km cinsinden
          };
        }
      }

      return nearestArea;
    } catch (e) {
      throw 'En yakın toplanma alanı bulunamadı: $e';
    }
  }
}
