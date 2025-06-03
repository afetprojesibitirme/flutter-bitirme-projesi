// lib/homepage.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services.dart';
import 'bluetooth_service.dart'; // Kendi BluetoothService'imiz
import 'emergency_display_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart'
    show DocumentSnapshot, GeoPoint;
import 'package:flutter/foundation.dart';
// flutter_blue_plus paketini FlutterBluePlus ve BluetoothAdapterState için 'fbp' ön eki ile import ediyoruz
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp
    hide BluetoothService;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final EmergencyServices _emergencyServices = EmergencyServices();
  final BluetoothService _bluetoothService =
      BluetoothService(); // Kendi servisimiz
  StreamSubscription? _gpsDataSubscription;
  StreamSubscription? _connectionStatusSubscription;

  Map<String, dynamic>? _lastReceivedGpsData;
  String _bluetoothStatus = "Yükleniyor...";
  bool _isProcessingAction = false;
  bool _isBuzzerOn = false; // Buzzer'ın anlık durumunu tutmak için

  @override
  void initState() {
    super.initState();
    _connectionStatusSubscription =
        _bluetoothService.connectionStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _bluetoothStatus = status;
        });
        if (status.contains("Bağlandı") || status.contains("Cihaz hazır")) {
          // Bağlantı sağlandığında ilk veri isteğini gönder
          // Sadece _lastReceivedGpsData daha önce alınmadıysa iste
          if (_lastReceivedGpsData == null ||
              (_lastReceivedGpsData!['latitude'] == 0.0 &&
                  _lastReceivedGpsData!['longitude'] == 0.0)) {
            _bluetoothService.requestGpsDataFromDevice();
          }
        }
      }
    });

    _gpsDataSubscription = _bluetoothService.gpsDataStream.listen((data) {
      if (mounted) {
        setState(() {
          _lastReceivedGpsData = data;
          _showSnackBar("ESP32'den yeni GPS verisi alındı.");
        });
      }
    });

    // Uygulama ilk açıldığında Bluetooth bağlantı durumunu kontrol et
    _checkBluetoothStateAndConnect();
  }

  Future<void> _checkBluetoothStateAndConnect() async {
    final state = await fbp.FlutterBluePlus.adapterState.first;
    if (state == fbp.BluetoothAdapterState.on) {
      _bluetoothService.scanAndConnect();
    } else {
      setState(() {
        _bluetoothStatus = "Bluetooth kapalı. Lütfen açın.";
      });
      // Kullanıcıdan Bluetooth'u açmasını isteyebilirsiniz (Android 12+ için gerekli)
      // await fbp.FlutterBluePlus.turnOn(); // Eğer otomatik açmak isterseniz fbp ile kullanın
    }
  }

  @override
  void dispose() {
    _gpsDataSubscription?.cancel();
    _connectionStatusSubscription?.cancel();
    _bluetoothService.dispose(); // Servisi temizle
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleEmergencyButtonPress() async {
    if (_isProcessingAction) return;
    setState(() {
      _isProcessingAction = true;
    });

    try {
      if (!_bluetoothService.isConnected() || _lastReceivedGpsData == null) {
        _showSnackBar(
            'ESP32\'ye bağlanın veya veri almayı bekleyin. Tekrar deneniyor...',
            isError: true);
        await _bluetoothService.scanAndConnect(); // Bağlantıyı tekrar dene
        // Veri gelene kadar beklemek veya kullanıcıya bilgi vermek gerekebilir
        await Future.delayed(
            const Duration(seconds: 3)); // Bağlantı ve veri alımı için bekle
        if (!_bluetoothService.isConnected() || _lastReceivedGpsData == null) {
          _showSnackBar(
              "ESP32'den geçerli veri alınamadı, mobil konum kullanılıyor.",
              isError: true);
        }
      }

      double latitude = _lastReceivedGpsData?['latitude'] ?? 0.0;
      double longitude = _lastReceivedGpsData?['longitude'] ?? 0.0;
      int satellites = _lastReceivedGpsData?['satellites'] ?? 0;

      String dataSource = "ESP32";

      // ESP32'den geçerli veri yoksa (0,0 koordinatları veya uydu sayısı düşükse) mobil cihazın konumunu kullan
      if ((latitude == 0.0 && longitude == 0.0) || satellites < 4) {
        _showSnackBar(
            'ESP32\'den geçerli GPS verisi alınamadı (uydu sayısı düşük veya konum 0,0). Mobil konum kullanılıyor.',
            isError: true);
        final mobilePosition =
            await _emergencyServices.getMobileDeviceCurrentLocation();
        latitude = mobilePosition.latitude;
        longitude = mobilePosition.longitude;
        satellites = 0; // Mobil konumdan uydu sayısı gelmez
        dataSource = "Mobile";
      }

      _showSnackBar('En yakın toplanma alanı hesaplanıyor...');
      final nearestAreaInfo = await _emergencyServices
          .findNearestRendezvousArea(latitude, longitude);

      _showSnackBar('Acil durum konumu kaydediliyor...');
      final DocumentSnapshot doc =
          await _emergencyServices.saveEmergencyLocation(
        latitude: latitude,
        longitude: longitude,
        esp32NearestAreaName: nearestAreaInfo['name'],
        esp32DistanceToAreaM: double.tryParse(nearestAreaInfo['distance_m']),
        // Yön bilgisi için ek hesaplama gerekebilir. Basit bir placeholder şimdilik.
        esp32DirectionToArea:
            "Bilinmiyor", // Todo: Gerçek yön hesaplaması eklenecek
        esp32Satellites: satellites,
        source: "${dataSource}_Acil_Buton",
      );

      _showSnackBar('Acil durum başarıyla kaydedildi!');
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                EmergencyDisplayPage(emergencyDataSnapshot: doc),
          ),
        );
      }
    } catch (e) {
      _showSnackBar('Hata: ${e.toString()}', isError: true);
      if (kDebugMode) print("Acil durum hatası: $e");
    } finally {
      setState(() {
        _isProcessingAction = false;
      });
    }
  }

  Future<void> _handleFindRendezvousArea() async {
    if (_isProcessingAction) return;
    setState(() {
      _isProcessingAction = true;
    });

    try {
      if (!_bluetoothService.isConnected() || _lastReceivedGpsData == null) {
        _showSnackBar(
            'ESP32\'ye bağlanın veya veri almayı bekleyin. Tekrar deneniyor...',
            isError: true);
        await _bluetoothService.scanAndConnect();
        await Future.delayed(
            const Duration(seconds: 3)); // Bağlantı ve veri alımı için bekle
        if (!_bluetoothService.isConnected() || _lastReceivedGpsData == null) {
          _showSnackBar("ESP32'den geçerli veri alınamadı, işlem iptal.",
              isError: true);
          return; // Geçerli veri yoksa işlemi durdur
        }
      }

      double latitude = _lastReceivedGpsData!['latitude'] ?? 0.0;
      double longitude = _lastReceivedGpsData!['longitude'] ?? 0.0;
      int satellites = _lastReceivedGpsData!['satellites'] ?? 0;

      if ((latitude == 0.0 && longitude == 0.0) || satellites < 4) {
        _showSnackBar(
            'ESP32\'den geçerli GPS verisi alınamadı (uydu sayısı düşük veya konum 0,0). İşlem iptal edildi.',
            isError: true);
        return; // Geçerli veri yoksa işlemi durdur
      }

      _showSnackBar('En yakın toplanma alanı bulunuyor...');
      final nearestAreaInfo = await _emergencyServices
          .findNearestRendezvousArea(latitude, longitude);

      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('En Yakın Toplanma Alanı'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Adı: ${nearestAreaInfo['name'] ?? 'Bilinmiyor'}'),
                  Text(
                      'Koordinatlar: ${nearestAreaInfo['coordinates']?.latitude.toStringAsFixed(6)}, ${nearestAreaInfo['coordinates']?.longitude.toStringAsFixed(6)}'),
                  Text('Mesafe: ${nearestAreaInfo['distance_m']} metre'),
                  Text('Mesafe: ${nearestAreaInfo['distance_km']} km'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Tamam'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    final lat = nearestAreaInfo['coordinates']?.latitude;
                    final lng = nearestAreaInfo['coordinates']?.longitude;
                    if (lat != null && lng != null) {
                      // Google Haritalar için genel URL yapısı
                      final url =
                          'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      } else {
                        _showSnackBar('Haritalar uygulaması başlatılamadı.',
                            isError: true);
                      }
                    } else {
                      _showSnackBar('Hedef koordinatlar geçersiz.',
                          isError: true);
                    }
                  },
                  child: const Text('Haritada Göster'),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      _showSnackBar('Hata: ${e.toString()}', isError: true);
      if (kDebugMode) print("Toplanma alanı hatası: $e");
    } finally {
      setState(() {
        _isProcessingAction = false;
      });
    }
  }

  Future<void> _tryToConnectBluetooth() async {
    if (_bluetoothService.isConnected()) {
      _showSnackBar('Zaten bağlı.');
      return;
    }
    setState(() {
      _bluetoothStatus = "Bağlanmaya çalışılıyor...";
    });
    await _bluetoothService.scanAndConnect();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    final buttonWidth = screenWidth * 0.8;
    final buttonHeight = screenHeight * 0.12; // Daha büyük butonlar için

    // Küçük ekranlarda butonların çok büyük olmaması için minimum/maksimum boyutlar
    final finalButtonWidth = buttonWidth.clamp(280.0, 400.0);
    final finalButtonHeight = buttonHeight.clamp(70.0, 100.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Acil Durum Yönetimi'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        actions: [
          IconButton(
            icon: Icon(Icons.bluetooth,
                color: _bluetoothService.isConnected()
                    ? Colors.greenAccent
                    : Colors.redAccent),
            onPressed: () {
              // Bluetooth bağlantı durumu bilgisi gösterme veya manuel bağlanma/kesme denemesi
              if (_bluetoothService.isConnected()) {
                _showSnackBar('Bluetooth bağlı: Bağlantı kesiliyor...');
                _bluetoothService.disconnectDevice();
              } else {
                _showSnackBar(
                    'Bluetooth bağlı değil: Bağlanmaya çalışılıyor...');
                _tryToConnectBluetooth();
              }
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.8),
              Theme.of(context).colorScheme.background
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        // BURADAKİ DÜZELTME: Column'u SingleChildScrollView ile sarmak
        child: SafeArea(
          child: SingleChildScrollView(
            // <-- Eklenen widget
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Sistem Durumu: $_bluetoothStatus',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _bluetoothStatus.contains("Bağlandı") ||
                              _bluetoothStatus.contains("Cihaz hazır")
                          ? Colors.green[800]
                          : Colors.red[800],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: screenHeight * 0.03),
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Son GPS Verisi (ESP32):',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _lastReceivedGpsData != null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        'Enlem: ${_lastReceivedGpsData!['latitude']?.toStringAsFixed(6) ?? 'N/A'}'),
                                    Text(
                                        'Boylam: ${_lastReceivedGpsData!['longitude']?.toStringAsFixed(6) ?? 'N/A'}'),
                                    Text(
                                        'Uydu Sayısı: ${_lastReceivedGpsData!['satellites']?.toString() ?? 'N/A'}'),
                                    Text(
                                        'Rakım (m): ${_lastReceivedGpsData!['altitude_m']?.toStringAsFixed(2) ?? 'N/A'}'),
                                    Text(
                                        'Yön (deg): ${_lastReceivedGpsData!['course_deg']?.toStringAsFixed(2) ?? 'N/A'}'),
                                    Text(
                                        'Hız (km/s): ${_lastReceivedGpsData!['speed_kmph']?.toStringAsFixed(2) ?? 'N/A'}'),
                                  ],
                                )
                              : const Text('Veri bekleniyor...'),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.05),
                  SizedBox(
                    width: finalButtonWidth,
                    height: finalButtonHeight,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessingAction
                          ? null
                          : _handleEmergencyButtonPress,
                      icon: Icon(Icons.warning_amber_rounded,
                          size: finalButtonHeight * 0.4),
                      label: Text('ACİL DURUM KONUMU KAYDET',
                          style: TextStyle(fontSize: finalButtonHeight * 0.25)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 15),
                      ),
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.025),
                  SizedBox(
                    width: finalButtonWidth,
                    height: finalButtonHeight,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessingAction
                          ? null
                          : _handleFindRendezvousArea,
                      icon: Icon(Icons.meeting_room_outlined,
                          size: finalButtonHeight * 0.4),
                      label: Text('TOPLANMA ALANI BUL',
                          style: TextStyle(fontSize: finalButtonHeight * 0.25)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 15),
                      ),
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.025),
                  SizedBox(
                    width: finalButtonWidth,
                    height: finalButtonHeight,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessingAction
                          ? null
                          : () {
                              if (!_bluetoothService.isConnected()) {
                                _showSnackBar(
                                    'Önce ESP32\'ye bağlanın veya bağlantıyı bekleyin.',
                                    isError: true);
                                _tryToConnectBluetooth();
                                return;
                              }
                              _bluetoothService.requestGpsDataFromDevice();
                              _showSnackBar(
                                  'ESP32\'den veri isteği gönderildi.');
                            },
                      icon: Icon(Icons.refresh_rounded,
                          size: finalButtonHeight * 0.4),
                      label: Text('ESP32 Veri Yenile',
                          style: TextStyle(fontSize: finalButtonHeight * 0.3)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey[600]),
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.025),
                  SizedBox(
                    width: finalButtonWidth,
                    height: finalButtonHeight,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessingAction
                          ? null
                          : () async {
                              if (!_bluetoothService.isConnected()) {
                                _showSnackBar(
                                    'Önce ESP32\'ye bağlanın veya bağlantıyı bekleyin.',
                                    isError: true);
                                _tryToConnectBluetooth();
                                return;
                              }
                              await _bluetoothService.toggleBuzzerOnDevice();
                              setState(() {
                                _isBuzzerOn =
                                    !_isBuzzerOn; // Durumu tersine çevir
                              });
                              _showSnackBar(_isBuzzerOn
                                  ? 'Buzzer Açıldı'
                                  : 'Buzzer Kapatıldı');
                            },
                      icon: Icon(
                          _isBuzzerOn
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          size: finalButtonHeight * 0.4),
                      label: Text(_isBuzzerOn ? 'Buzzer Kapat' : 'Buzzer Aç',
                          style: TextStyle(fontSize: finalButtonHeight * 0.3)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _isBuzzerOn
                              ? Colors.orange[800]
                              : Colors.grey[600]),
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.025), // En alttaki boşluk
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
