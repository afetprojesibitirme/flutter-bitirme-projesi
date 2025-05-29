import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore, FieldValue, GeoPoint, DocumentSnapshot;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      
      // Profil bilgilerini SharedPreferences'dan al
      final prefs = await SharedPreferences.getInstance();
      String adSoyad = prefs.getString('adSoyad') ?? 'Bilinmeyen Kullanıcı';
      String yas = prefs.getString('yas') ?? '';
      String kanGrubu = prefs.getString('kanGrubu') ?? '';
      String hastaliklar = prefs.getString('hastaliklar') ?? '';

      // Create GeoPoint instance
      final geoPoint = GeoPoint(position.latitude, position.longitude);

      if (adSoyad == 'Bilinmeyen Kullanıcı'|| yas== ''|| kanGrubu == '' || hastaliklar == ''){
        throw 'Lutfen profil sayfasından bilgilerinizi girin';
      }

      // Dokümanı kullanıcının adıyla oluştur
      await _firestore.collection('emergency').doc(adSoyad).set({
        'nameSurname': adSoyad,
        'age': yas,
        'blood': kanGrubu,
        'conditions': hastaliklar,
        'location': geoPoint,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving emergency location: $e');
      throw 'Konum kaydedilemedi: $e';
    }
  }

  // En yakın toplanma alanını bul
  Future<Map<String, dynamic>> findNearestGatheringArea() async {
    try {
      // Get current location
      Position currentPosition = await getCurrentLocation();

      // Get areas document from Firestore
      final areaDoc = await _firestore.collection('area').doc('areas').get();

      if (!areaDoc.exists || !areaDoc.data()!.containsKey('areasarray')) {
        throw 'Alan bulunamadı';
      }

      List<dynamic> areasList = areaDoc.data()!['areasarray'] as List<dynamic>;
      
      if (areasList.isEmpty) {
        throw 'Alan bulunamadı';
      }

      double minDistance = double.infinity;
      Map<String, dynamic> nearestArea = {};

      for (GeoPoint geoPoint in areasList) {
        double distance = Geolocator.distanceBetween(
          currentPosition.latitude,
          currentPosition.longitude,
          geoPoint.latitude,
          geoPoint.longitude,
        );

        if (distance < minDistance) {
          minDistance = distance;
          nearestArea = {
            'coordinates': '${geoPoint.latitude}, ${geoPoint.longitude}',
            'distance': (distance / 1000).toStringAsFixed(2), // km cinsinden
          };
        }
      }

      if (nearestArea.isEmpty) {
        throw 'Alan bulunamadı';
      }

      return nearestArea;
    } catch (e) {
      print('Error finding nearest area: $e');
      throw 'Alan bulunamadı';
    }
  }
}
