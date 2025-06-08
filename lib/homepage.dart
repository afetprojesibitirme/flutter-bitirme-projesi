// lib/homepage.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services.dart';
import 'bluetooth_service.dart'; // Kendi BluetoothService'imiz
import 'emergency_display_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart'
    show DocumentSnapshot, GeoPoint; // Removed unused FieldValue
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'navbar.dart'; // Added NavBar import

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
  // ADDED: Subscription for ESP32 emergency trigger
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
          // Only show snackbar if it's not an ESP32 emergency signal (that one will have its own message)
          if (data['is_esp32_emergency'] == null ||
              data['is_esp32_emergency'] == false) {
            _showSnackBar("ESP32'den yeni GPS verisi alındı.");
          }
        });
      } else {
        _lastReceivedGpsData =
            data; // Still update data if not mounted for background logic
      }
    });

    // ADDED: Listen to ESP32 emergency trigger
    _esp32EmergencySubscription = _bluetoothService.esp32EmergencyTriggerStream
        .listen((Map<String, dynamic> emergencyGpsData) async {
      if (kDebugMode) {
        print(
            "ESP32 Emergency Signal Received in HomePage with data: $emergencyGpsData");
      }
      if (_isProcessingAction) {
        if (kDebugMode)
          print("Action already in progress. Ignoring ESP32 emergency signal.");
        return;
      }

      // Update _lastReceivedGpsData with the data that came with the emergency signal
      if (mounted) {
        setState(() {
          _lastReceivedGpsData = emergencyGpsData;
        });
      } else {
        _lastReceivedGpsData = emergencyGpsData; // Update for background logic
      }

      _showSnackBar(
          "ESP32 Acil Durum Butonu Sinyali Alındı! İşlem Başlatılıyor...");
      await _handleEmergencyButtonPress(isFromEsp32Button: true);
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
      } else {
        _bluetoothStatus = "Bluetooth kapalı. Lütfen açın.";
      }
    }
  }

  @override
  void dispose() {
    _gpsDataSubscription?.cancel();
    _connectionStatusSubscription?.cancel();
    _esp32EmergencySubscription?.cancel(); // ADDED: Cancel new subscription
    _bluetoothService.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) {
      if (kDebugMode)
        print("Snackbar suppressed: HomePage not mounted. Message: $message");
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // MODIFIED: Added isFromEsp32Button parameter and guarded setState
  Future<void> _handleEmergencyButtonPress(
      {bool isFromEsp32Button = false}) async {
    if (_isProcessingAction && !isFromEsp32Button)
      return; // UI button can be blocked by _isProcessingAction

    // For ESP32 button, _isProcessingAction is checked before calling this.
    // Here, we ensure it's set for the duration of this function.
    if (mounted) {
      setState(() {
        _isProcessingAction = true;
      });
    } else {
      _isProcessingAction =
          true; // Manage state for logic flow even if not mounted
    }

    try {
      // Use _lastReceivedGpsData which should have been updated by the GPS stream or ESP32 emergency stream
      if (!_bluetoothService.isConnected() ||
          _lastReceivedGpsData == null ||
          (_lastReceivedGpsData!['latitude'] == 0.0 &&
              _lastReceivedGpsData!['longitude'] == 0.0)) {
        _showSnackBar(
            'ESP32\'ye bağlanın veya geçerli veri almayı bekleyin. Tekrar deneniyor...',
            isError: true);
        if (!_bluetoothService.isConnected()) {
          await _bluetoothService.scanAndConnect(); // Bağlantıyı tekrar dene
        }
        // Veri gelene kadar beklemek veya kullanıcıya bilgi vermek gerekebilir
        await Future.delayed(const Duration(seconds: 3));
        if (!_bluetoothService.isConnected() ||
            _lastReceivedGpsData == null ||
            (_lastReceivedGpsData!['latitude'] == 0.0 &&
                _lastReceivedGpsData!['longitude'] == 0.0)) {
          _showSnackBar(
              "ESP32'den geçerli veri alınamadı, mobil konum kullanılıyor.",
              isError: true);
        }
      }

      double latitude = _lastReceivedGpsData?['latitude'] ?? 0.0;
      double longitude = _lastReceivedGpsData?['longitude'] ?? 0.0;
      int satellites = _lastReceivedGpsData?['satellites'] ?? 0;

      // MODIFIED: More specific data source
      String dataSource =
          isFromEsp32Button ? "ESP32_Button" : "Mobile_App_Button";

      if ((latitude == 0.0 && longitude == 0.0) || satellites < 4) {
        _showSnackBar(
            'ESP32\'den geçerli GPS verisi alınamadı (uydu sayısı düşük veya konum 0,0). Mobil konum kullanılıyor.',
            isError: true);
        final mobilePosition =
            await _emergencyServices.getMobileDeviceCurrentLocation();
        latitude = mobilePosition.latitude;
        longitude = mobilePosition.longitude;
        satellites = 0;
        // MODIFIED: More specific data source for fallback
        dataSource = isFromEsp32Button
            ? "ESP32_Button_Mobile_Fallback"
            : "Mobile_App_Button_Mobile_Fallback";
      }

      _showSnackBar('En yakın toplanma alanı hesaplanıyor...');
      final nearestAreaInfo = await _emergencyServices
          .findNearestRendezvousArea(latitude, longitude);

      // Null check for coordinates before saving
      final coordinates = nearestAreaInfo['coordinates'];
      double? areaLat;
      double? areaLng;
      if (coordinates != null) {
        areaLat = coordinates.latitude;
        areaLng = coordinates.longitude;
      }

      _showSnackBar('Acil durum konumu kaydediliyor...');
      final DocumentSnapshot doc =
          await _emergencyServices.saveEmergencyLocation(
        latitude: latitude,
        longitude: longitude,
        esp32NearestAreaName: nearestAreaInfo['name'],
        esp32DistanceToAreaM: double.tryParse(nearestAreaInfo['distance_m']
            .toString()), // Ensure string then parse
        esp32DirectionToArea: "Bilinmiyor",
        esp32Satellites: satellites,
        // MODIFIED: Use the determined dataSource directly
        source: dataSource,
      );

      _showSnackBar('Acil durum başarıyla kaydedildi!');
      if (mounted) {
        // Navigation only if mounted
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                EmergencyDisplayPage(emergencyDataSnapshot: doc),
          ),
        );
      } else {
        if (kDebugMode)
          print(
              "Emergency data saved. HomePage not mounted, skipping navigation to EmergencyDisplayPage.");
        // Potentially trigger a local notification here if app is in background
      }
    } catch (e) {
      _showSnackBar('Hata: ${e.toString()}', isError: true);
      if (kDebugMode) print("Acil durum hatası: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingAction = false;
        });
      } else {
        _isProcessingAction = false; // Reset state
      }
    }
  }

  Future<void> _handleFindRendezvousArea() async {
    if (_isProcessingAction) return;
    if (mounted)
      setState(() {
        _isProcessingAction = true;
      });
    else
      _isProcessingAction = true;

    try {
      double latitude = 0.0;
      double longitude = 0.0;
      int satellites = 0;

      // Try to get ESP32 data
      if (_bluetoothService.isConnected() &&
          _lastReceivedGpsData != null &&
          (_lastReceivedGpsData!['latitude'] != 0.0 ||
              _lastReceivedGpsData!['longitude'] != 0.0) &&
          (_lastReceivedGpsData!['satellites'] ?? 0) >= 4) {
        latitude = _lastReceivedGpsData!['latitude'] ?? 0.0;
        longitude = _lastReceivedGpsData!['longitude'] ?? 0.0;
        satellites = _lastReceivedGpsData!['satellites'] ?? 0;
      } else {
        // Fallback to phone location
        _showSnackBar("ESP32'den geçerli veri alınamadı, telefon konumu kullanılıyor.", isError: true);
        final mobilePosition = await _emergencyServices.getMobileDeviceCurrentLocation();
        latitude = mobilePosition.latitude;
        longitude = mobilePosition.longitude;
        satellites = 0;
      }

      _showSnackBar('En yakın toplanma alanı bulunuyor...');
      final nearestAreaInfo = await _emergencyServices.findNearestRendezvousArea(latitude, longitude);

      if (mounted) {
        // Dialog only if mounted
        showDialog(
          context: context,
          builder: (BuildContext context) {
            final coordinates = nearestAreaInfo['coordinates'];
            String latStr = coordinates != null ? coordinates.latitude.toStringAsFixed(6) : 'N/A';
            String lngStr = coordinates != null ? coordinates.longitude.toStringAsFixed(6) : 'N/A';
            return AlertDialog(
              title: const Text('En Yakın Toplanma Alanı'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Adı: ${nearestAreaInfo['name'] ?? 'Bilinmiyor'}'),
                  Text('Koordinatlar: $latStr, $lngStr'),
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
                    final lat = coordinates != null ? coordinates.latitude : null;
                    final lng = coordinates != null ? coordinates.longitude : null;
                    if (lat != null && lng != null) {
                      final url =
                          'https://www.google.com/maps/search/?api=1&query=$lat,$lng'; // More reliable maps URL
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
      if (mounted)
        setState(() {
          _isProcessingAction = false;
        });
      else
        _isProcessingAction = false;
    }
  }

  Future<void> _tryToConnectBluetooth() async {
    if (_bluetoothService.isConnected()) {
      _showSnackBar('Zaten bağlı.');
      return;
    }
    if (mounted) {
      setState(() {
        _bluetoothStatus = "Bağlanmaya çalışılıyor...";
      });
    } else {
      _bluetoothStatus = "Bağlanmaya çalışılıyor...";
    }
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
                  // Added padding for better visibility
                  padding: const EdgeInsets.all(8.0),
                  child: Card(
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
                            'Sistem Durumu:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
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
                        _lastReceivedGpsData != null &&
                                (_lastReceivedGpsData!['latitude'] != 0.0 ||
                                    _lastReceivedGpsData!['longitude'] != 0.0)
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
                                  if (_lastReceivedGpsData!['is_esp32_emergency'] ==
                                      true)
                                    const Text('Sinyal: ESP32 Acil Butonu',
                                        style: TextStyle(
                                            color: Colors.orangeAccent)),
                                ],
                              )
                            : const Text(
                                'Veri bekleniyor veya geçerli değil...'),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: screenHeight * 0.04), // Adjusted spacing
                SizedBox(
                  width: finalButtonWidth,
                  height: finalButtonHeight,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessingAction
                        ? () {} // Empty function instead of null
                        : () => _handleEmergencyButtonPress(),
                    icon: Icon(Icons.warning_amber_rounded,
                        size: finalButtonHeight * 0.4),
                    label: Text('ACİL DURUM KONUMU KAYDET',
                        style: TextStyle(
                            fontSize: finalButtonHeight * 0.22)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isProcessingAction 
                          ? Colors.red[700]?.withOpacity(0.5)
                          : Colors.red[700],
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
                        ? () {} // Empty function instead of null
                        : _handleFindRendezvousArea,
                    icon: Icon(Icons.meeting_room_outlined,
                        size: finalButtonHeight * 0.4),
                    label: Text('TOPLANMA ALANI BUL',
                        style: TextStyle(
                            fontSize: finalButtonHeight * 0.22)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isProcessingAction 
                          ? Colors.green[700]?.withOpacity(0.5)
                          : Colors.green[700],
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
                  height: finalButtonHeight * 0.8,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessingAction
                        ? () {} // Empty function instead of null
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
                        ? () {} // Empty function instead of null
                        : () async {
                            if (!_bluetoothService.isConnected()) {
                              _showSnackBar(
                                  'Önce ESP32\'ye bağlanın veya bağlantıyı bekleyin.',
                                  isError: true);
                              _tryToConnectBluetooth();
                              return;
                            }
                            await _bluetoothService.toggleBuzzerOnDevice();
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
