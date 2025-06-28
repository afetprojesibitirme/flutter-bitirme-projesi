// lib/homepage.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services.dart';
import 'bluetooth_service.dart';
import 'emergency_display_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart'
    show DocumentSnapshot, GeoPoint;
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'navbar.dart'; // Mevcut import korundu

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final EmergencyServices _emergencyServices = EmergencyServices();
  final BluetoothService _bluetoothService = BluetoothService();
  StreamSubscription? _gpsDataSubscription;
  StreamSubscription? _connectionStatusSubscription;
  // YENİ: ESP32 acil durum butonu için dinleyici
  StreamSubscription<Map<String, dynamic>>? _esp32EmergencySubscription;

  Map<String, dynamic>? _lastReceivedGpsData;
  String _bluetoothStatus = "Yükleniyor...";
  bool _isProcessingAction = false;
  bool _isBuzzerOn = false;

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
          if (_lastReceivedGpsData == null ||
              (_lastReceivedGpsData!['latitude'] == 0.0)) {
            _bluetoothService.requestGpsDataFromDevice();
          }
        }
      }
    });

    _gpsDataSubscription = _bluetoothService.gpsDataStream.listen((data) {
      if (mounted) {
        setState(() {
          _lastReceivedGpsData = data;
        });
        if (data['is_esp32_emergency'] != true) {
          _showSnackBar("ESP32'den yeni GPS verisi alındı.");
        }
      }
    });

    // YENİ: ESP32 acil durum sinyalini dinle
    _esp32EmergencySubscription = _bluetoothService.esp32EmergencyTriggerStream
        .listen((emergencyGpsData) {
      if (mounted && !_isProcessingAction) {
        _showSnackBar("ESP32 Acil Durum Butonu Sinyali Alındı!", isError: true);
        // Gelen veriyle acil durum fonksiyonunu tetikle
        _handleEmergencyButtonPress(
            isFromEsp32Button: true, initialData: emergencyGpsData);
      }
    });

    _checkBluetoothStateAndConnect();
  }

  Future<void> _checkBluetoothStateAndConnect() async {
    final state = await fbp.FlutterBluePlus.adapterState.first;
    if (state == fbp.BluetoothAdapterState.on) {
      _bluetoothService.scanAndConnect();
    } else {
      if (mounted) {
        setState(() {
          _bluetoothStatus = "Bluetooth kapalı. Lütfen açın.";
        });
      }
    }
  }

  @override
  void dispose() {
    _gpsDataSubscription?.cancel();
    _connectionStatusSubscription?.cancel();
    _esp32EmergencySubscription?.cancel(); // YENİ
    _bluetoothService.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // DEĞİŞTİ: Fonksiyon yönü hesaplayıp gönderecek ve kaydedecek şekilde güncellendi
  Future<void> _handleEmergencyButtonPress({
    bool isFromEsp32Button = false,
    Map<String, dynamic>? initialData,
  }) async {
    if (_isProcessingAction) return;
    if (mounted) setState(() => _isProcessingAction = true);

    try {
      final gpsData = initialData ?? _lastReceivedGpsData;
      double latitude = gpsData?['latitude'] ?? 0.0;
      double longitude = gpsData?['longitude'] ?? 0.0;
      int satellites = gpsData?['satellites'] ?? 0;
      String dataSource =
          isFromEsp32Button ? "ESP32_Button" : "Mobile_App_Button";

      if (!_bluetoothService.isConnected() && isFromEsp32Button) {
        // ESP32'den sinyal geldi ama bağlantı görünmüyorsa, mobil konuma geçmek mantıklı olabilir.
        satellites = 0;
      }

      if (satellites < 4) {
        _showSnackBar(
            'GPS verisi yetersiz (uydu < 4). Mobil konum kullanılıyor.',
            isError: true);
        final mobilePosition =
            await _emergencyServices.getMobileDeviceCurrentLocation();
        latitude = mobilePosition.latitude;
        longitude = mobilePosition.longitude;
        dataSource += "_Mobile_Fallback";
      }

      if (latitude == 0.0 && longitude == 0.0) {
        throw Exception(
            'Geçerli bir konum alınamadı (0,0). İşlem iptal edildi.');
      }

      _showSnackBar('En yakın toplanma alanı ve yön hesaplanıyor...');
      final nearestAreaInfo = await _emergencyServices
          .findNearestRendezvousArea(latitude, longitude);

      final double? bearing = nearestAreaInfo['bearing_deg'];
      final String? directionAbbr = nearestAreaInfo['direction_abbr'];

      if (bearing != null && _bluetoothService.isConnected()) {
        await _bluetoothService.sendDirectionToDevice(bearing);
        _showSnackBar("Yön bilgisi ($directionAbbr) ESP32'ye gönderildi.");
      }

      _showSnackBar('Acil durum konumu kaydediliyor...');
      final DocumentSnapshot doc =
          await _emergencyServices.saveEmergencyLocation(
        latitude: latitude,
        longitude: longitude,
        esp32NearestAreaName: nearestAreaInfo['name'],
        esp32DistanceToAreaM: double.tryParse(nearestAreaInfo['distance_m']),
        esp32DirectionToArea:
            directionAbbr, // Firestore'a "Bilinmiyor" yerine hesaplanan yönü kaydet
        esp32Satellites: satellites,
        source: dataSource,
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
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  // DEĞİŞTİ: Bu fonksiyon da artık yönü ESP32'ye gönderiyor ve dialogda gösteriyor
  Future<void> _handleFindRendezvousArea() async {
    if (_isProcessingAction) return;
    if (mounted) setState(() => _isProcessingAction = true);

    try {
      double latitude = 0.0;
      double longitude = 0.0;

      if (_bluetoothService.isConnected() &&
          _lastReceivedGpsData != null &&
          (_lastReceivedGpsData!['satellites'] ?? 0) >= 4) {
        latitude = _lastReceivedGpsData!['latitude'] ?? 0.0;
        longitude = _lastReceivedGpsData!['longitude'] ?? 0.0;
        _showSnackBar("ESP32 konumu kullanılıyor...");
      } else {
        _showSnackBar(
            "ESP32'den geçerli veri alınamadı, telefon konumu kullanılıyor.",
            isError: true);
        final mobilePosition =
            await _emergencyServices.getMobileDeviceCurrentLocation();
        latitude = mobilePosition.latitude;
        longitude = mobilePosition.longitude;
      }

      _showSnackBar('En yakın toplanma alanı bulunuyor...');
      final nearestAreaInfo = await _emergencyServices
          .findNearestRendezvousArea(latitude, longitude);

      final double? bearing = nearestAreaInfo['bearing_deg'];
      final String? directionAbbr = nearestAreaInfo['direction_abbr'];

      if (bearing != null && _bluetoothService.isConnected()) {
        await _bluetoothService.sendDirectionToDevice(bearing);
        _showSnackBar("Yön bilgisi ($directionAbbr) ESP32'ye gönderildi.");
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            final coordinates = nearestAreaInfo['coordinates'] as GeoPoint?;
            return AlertDialog(
              title: const Text('En Yakın Toplanma Alanı'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Adı: ${nearestAreaInfo['name'] ?? 'Bilinmiyor'}'),
                  Text(
                      'Koordinatlar: ${coordinates?.latitude.toStringAsFixed(6)}, ${coordinates?.longitude.toStringAsFixed(6)}'),
                  Text('Mesafe: ${nearestAreaInfo['distance_m']} metre'),
                  Text('Yön: $directionAbbr',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Tamam')),
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    final lat = coordinates?.latitude;
                    final lng = coordinates?.longitude;
                    if (lat != null && lng != null) {
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
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  Future<void> _tryToConnectBluetooth() async {
    if (_bluetoothService.isConnected()) {
      _showSnackBar('Zaten bağlı.');
      return;
    }
    if (mounted) setState(() => _bluetoothStatus = "Bağlanmaya çalışılıyor...");
    await _bluetoothService.scanAndConnect();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final baseButtonWidth = screenWidth * 0.8;
    final baseButtonHeight = screenHeight * 0.12;
    final finalButtonWidth = baseButtonWidth.clamp(280.0, 400.0);
    final finalButtonHeight = baseButtonHeight.clamp(70.0, 100.0);

    return Scaffold(
      backgroundColor: Colors.white12,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Sistem Durumu:',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _bluetoothStatus,
                            style: TextStyle(
                              fontSize: 16,
                              color: _bluetoothStatus.contains("Bağlandı") ||
                                      _bluetoothStatus.contains("Cihaz hazır")
                                  ? Colors.lightGreenAccent[700]
                                  : Colors.redAccent[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: screenHeight * 0.02),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Son GPS Verisi (ESP32):',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        _lastReceivedGpsData != null &&
                                (_lastReceivedGpsData!['latitude'] != 0.0)
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      'Enlem: ${_lastReceivedGpsData!['latitude']?.toStringAsFixed(6) ?? 'N/A'}'),
                                  Text(
                                      'Boylam: ${_lastReceivedGpsData!['longitude']?.toStringAsFixed(6) ?? 'N/A'}'),
                                  Text(
                                      'Uydu Sayısı: ${_lastReceivedGpsData!['satellites']?.toString() ?? 'N/A'}'),
                                ],
                              )
                            : const Text(
                                'Veri bekleniyor veya geçerli değil...'),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: screenHeight * 0.04),
                SizedBox(
                  width: finalButtonWidth,
                  height: finalButtonHeight,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessingAction
                        ? () {}
                        : _handleEmergencyButtonPress,
                    icon: Icon(Icons.warning_amber_rounded,
                        size: finalButtonHeight * 0.4),
                    label: Text('ACİL DURUM KONUMU KAYDET',
                        style: TextStyle(fontSize: finalButtonHeight * 0.22)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isProcessingAction
                          ? Colors.red[700]?.withOpacity(0.5)
                          : Colors.red[700],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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
                    onPressed:
                        _isProcessingAction ? () {} : _handleFindRendezvousArea,
                    icon: Icon(Icons.meeting_room_outlined,
                        size: finalButtonHeight * 0.4),
                    label: Text('TOPLANMA ALANI BUL',
                        style: TextStyle(fontSize: finalButtonHeight * 0.22)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isProcessingAction
                          ? Colors.green[700]?.withOpacity(0.5)
                          : Colors.green[700],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 15),
                    ),
                  ),
                ),
                SizedBox(height: screenHeight * 0.025),
                SizedBox(
                  width: finalButtonWidth,
                  height: finalButtonHeight * 0.8,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessingAction
                        ? () {}
                        : () {
                            if (!_bluetoothService.isConnected()) {
                              _showSnackBar('Önce ESP32\'ye bağlanın.',
                                  isError: true);
                              _tryToConnectBluetooth();
                              return;
                            }
                            _bluetoothService.requestGpsDataFromDevice();
                            _showSnackBar('ESP32\'den veri isteği gönderildi.');
                          },
                    icon: Icon(Icons.refresh_rounded,
                        size: finalButtonHeight * 0.3),
                    label: Text('ESP32 Veri Yenile',
                        style: TextStyle(fontSize: finalButtonHeight * 0.22)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isProcessingAction
                          ? Colors.blueGrey[600]?.withOpacity(0.5)
                          : Colors.blueGrey[600],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                SizedBox(height: screenHeight * 0.025),
                SizedBox(
                  width: finalButtonWidth,
                  height: finalButtonHeight * 0.8,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessingAction
                        ? () {}
                        : () async {
                            if (!_bluetoothService.isConnected()) {
                              _showSnackBar('Önce ESP32\'ye bağlanın.',
                                  isError: true);
                              _tryToConnectBluetooth();
                              return;
                            }
                            await _bluetoothService.toggleBuzzerOnDevice();
                            // DEĞİŞTİ: UI'da anlık geri bildirim için yerel state'i de güncelleyelim.
                            setState(() => _isBuzzerOn = !_isBuzzerOn);
                            _showSnackBar(
                                'Buzzer komutu ESP32\'ye gönderildi.');
                          },
                    icon: Icon(
                        _isBuzzerOn
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        size: finalButtonHeight * 0.3),
                    label: Text('Buzzer Aç/Kapat',
                        style: TextStyle(fontSize: finalButtonHeight * 0.22)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isProcessingAction
                          ? Colors.orange[700]?.withOpacity(0.5)
                          : Colors.orange[700],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                SizedBox(height: screenHeight * 0.03),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const NavBar(selectedIndex: 1),
    );
  }
}
