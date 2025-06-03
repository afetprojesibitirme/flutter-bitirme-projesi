import 'dart:async';
import 'dart:convert'; // json.decode, utf8.decode için
import 'package:flutter/foundation.dart';
// flutter_blue_plus paketini 'fbp' ön eki ile import ediyoruz
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

// ESP32 Kodundaki UUID'ler ile aynı olmalı
const String esp32DeviceName = "ESP32_GPS_Tracker";
const String serviceUuidString = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String characteristicUuidGpsDataString =
    "beb5483e-36e1-4688-b7f5-ea07361b26a8";
const String characteristicUuidCommandString =
    "f27b53ad-39c1-4c60-b1ff-ff97c2af3788";

class BluetoothService {
  fbp.BluetoothDevice? _connectedDevice;
  fbp.BluetoothCharacteristic? _gpsDataCharacteristic;
  fbp.BluetoothCharacteristic? _commandCharacteristic;
  StreamSubscription<fbp.BluetoothConnectionState>?
      _connectionStateSubscription;
  StreamSubscription<List<int>>? _gpsValueSubscription;

  final StreamController<Map<String, dynamic>> _gpsDataStreamController =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get gpsDataStream =>
      _gpsDataStreamController.stream;

  final StreamController<String> _connectionStatusStreamController =
      StreamController.broadcast();
  Stream<String> get connectionStatusStream =>
      _connectionStatusStreamController.stream;

  // ADDED: StreamController for ESP32 emergency trigger
  final StreamController<Map<String, dynamic>>
      _esp32EmergencyTriggerController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get esp32EmergencyTriggerStream =>
      _esp32EmergencyTriggerController.stream;

  BluetoothService() {
    fbp.FlutterBluePlus.adapterState.listen((state) {
      if (kDebugMode) print("Bluetooth Adaptör Durumu: $state");
      if (state == fbp.BluetoothAdapterState.on) {
        _connectionStatusStreamController
            .add("Bluetooth Açık, Cihaz Aranıyor...");
        scanAndConnect();
      } else {
        _connectionStatusStreamController.add("Bluetooth Kapalı: $state");
        disconnectDevice();
      }
    });
    _checkInitialConnection();
  }

  Future<void> _checkInitialConnection() async {
    try {
      List<fbp.BluetoothDevice> connectedDevices =
          await fbp.FlutterBluePlus.connectedDevices;
      if (connectedDevices.isNotEmpty) {
        fbp.BluetoothDevice? esp32 = connectedDevices.firstWhereOrNull(
          (d) => d.platformName == esp32DeviceName,
        );
        if (esp32 != null) {
          _connectedDevice = esp32;
          await _discoverServicesAndCharacteristics();
          _connectionStatusStreamController
              .add("Önceden Bağlı: ${esp32.platformName}");
          return;
        }
      }
      _connectionStatusStreamController.add("Cihaz Aranıyor...");
      scanAndConnect();
    } catch (e) {
      if (kDebugMode) print("Initial connection check error: $e");
      _connectionStatusStreamController
          .add("Hata: Başlangıç Bağlantı Kontrolü");
    }
  }

  Future<void> scanAndConnect() async {
    if (await fbp.FlutterBluePlus.isScanning.first) {
      if (kDebugMode) print("Zaten taranıyor, yeni tarama başlatılmıyor.");
      return;
    }
    if (isConnected()) {
      _connectionStatusStreamController.add("Zaten bağlı.");
      return;
    }

    _connectionStatusStreamController.add("Cihaz Taranıyor...");
    try {
      var subscription = fbp.FlutterBluePlus.scanResults.listen(
        (results) async {
          for (fbp.ScanResult r in results) {
            if (kDebugMode)
              print(
                  'Bulunan Cihaz: ${r.device.platformName} - ${r.device.remoteId}');
            if (r.device.platformName == esp32DeviceName) {
              fbp.FlutterBluePlus.stopScan();
              _connectedDevice = r.device;
              _connectionStatusStreamController.add(
                  "Cihaz Bulundu: ${r.device.platformName}. Bağlanılıyor...");
              try {
                await _connectedDevice!.connect(
                  timeout: const Duration(seconds: 10),
                  autoConnect: false,
                );
                await _discoverServicesAndCharacteristics();
                _connectionStatusStreamController
                    .add("Cihaz Bağlandı: ${r.device.platformName}");
                _listenToConnectionState();
                requestGpsDataFromDevice();
              } catch (e) {
                if (kDebugMode) print("Bağlantı Hatası: $e");
                _connectionStatusStreamController.add("Bağlantı Hatası: $e");
                _connectedDevice = null;
                Future.delayed(
                    const Duration(seconds: 2), () => scanAndConnect());
              }
              return;
            }
          }
        },
      );

      fbp.FlutterBluePlus.cancelWhenScanComplete(subscription);
      await fbp.FlutterBluePlus.startScan(
        withNames: [esp32DeviceName],
        timeout: const Duration(seconds: 15),
      );
      if (_connectedDevice == null) {
        _connectionStatusStreamController
            .add("Cihaz bulunamadı, tekrar deneniyor...");
        Future.delayed(const Duration(seconds: 2), () => scanAndConnect());
      }
    } catch (e) {
      if (kDebugMode) print("Tarama Hatası: $e");
      _connectionStatusStreamController.add("Tarama Hatası: $e");
      if (await fbp.FlutterBluePlus.isScanning.first) {
        fbp.FlutterBluePlus.stopScan();
      }
    }
  }

  Future<void> _discoverServicesAndCharacteristics() async {
    if (_connectedDevice == null) {
      _connectionStatusStreamController.add("Hata: Bağlı cihaz yok.");
      return;
    }
    try {
      List<fbp.BluetoothService> services =
          await _connectedDevice!.discoverServices();
      for (var service in services) {
        if (service.uuid.toString() == serviceUuidString) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString() ==
                characteristicUuidGpsDataString) {
              _gpsDataCharacteristic = characteristic;
              if (characteristic.properties.notify ||
                  characteristic.properties.indicate) {
                await characteristic.setNotifyValue(true);
                _gpsValueSubscription
                    ?.cancel(); // Cancel previous subscription if any
                _gpsValueSubscription =
                    characteristic.lastValueStream.listen((value) {
                  if (value.isNotEmpty) {
                    try {
                      String jsonString = utf8.decode(value);
                      if (kDebugMode) print("Alınan GPS JSON: $jsonString");
                      Map<String, dynamic> gpsData = json.decode(jsonString);

                      // MODIFIED: Check for ESP32 emergency flag
                      if (gpsData.containsKey('is_esp32_emergency') &&
                          gpsData['is_esp32_emergency'] == true) {
                        if (kDebugMode)
                          print(
                              "ESP32 Emergency Signal Received via GPS data characteristic!");
                        // Send the whole GPS data packet through the emergency stream
                        _esp32EmergencyTriggerController.add(gpsData);
                      }
                      // Always send the GPS data to the general GPS data stream
                      _gpsDataStreamController.add(gpsData);
                    } catch (e) {
                      if (kDebugMode)
                        print(
                            "GPS JSON parse hatası: $e, Veri: ${utf8.decode(value)}");
                    }
                  }
                });
                _connectionStatusStreamController
                    .add("Cihaz hazır: GPS karakteristik alındı.");
              } else {
                if (kDebugMode)
                  print("GPS karakteristik notify/indicate desteklemiyor.");
              }
            } else if (characteristic.uuid.toString() ==
                characteristicUuidCommandString) {
              _commandCharacteristic = characteristic;
              _connectionStatusStreamController
                  .add("Cihaz hazır: Komut karakteristik alındı.");
            }
          }
        }
      }
      if (_gpsDataCharacteristic == null || _commandCharacteristic == null) {
        _connectionStatusStreamController
            .add("Uyarı: Bazı karakteristikler bulunamadı.");
        disconnectDevice();
      }
    } catch (e) {
      if (kDebugMode) print("Servis ve Karakteristik Keşif Hatası: $e");
      _connectionStatusStreamController.add("Hata: Servis/Karakteristik Keşfi");
      disconnectDevice();
    }
  }

  void _listenToConnectionState() {
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription =
        _connectedDevice?.connectionState.listen((state) {
      if (kDebugMode) print("Bağlantı Durumu Değişti: $state");
      if (state == fbp.BluetoothConnectionState.disconnected) {
        _connectionStatusStreamController.add("Bağlantı Kesildi.");
        _connectedDevice = null;
        _gpsDataCharacteristic = null;
        _commandCharacteristic = null;
        _gpsValueSubscription?.cancel();
        _gpsValueSubscription = null;
        Future.delayed(const Duration(seconds: 2), () {
          if (!isConnected()) {
            scanAndConnect();
          }
        });
      } else if (state == fbp.BluetoothConnectionState.connected) {
        _connectionStatusStreamController.add("Yeniden Bağlandı.");
        _discoverServicesAndCharacteristics();
      }
    });
  }

  Future<void> requestGpsDataFromDevice() async {
    if (_connectedDevice == null || _commandCharacteristic == null) {
      _connectionStatusStreamController
          .add("Cihaz bağlı değil veya komut karakteristiği yok.");
      return;
    }
    try {
      await _commandCharacteristic!
          .write(utf8.encode("REQUEST_GPS"), withoutResponse: true);
      if (kDebugMode) print("REQUEST_GPS komutu gönderildi.");
    } catch (e) {
      if (kDebugMode) print("REQUEST_GPS komutu gönderme hatası: $e");
      _connectionStatusStreamController.add("Hata: Veri isteği gönderilemedi.");
    }
  }

  Future<void> toggleBuzzerOnDevice() async {
    if (_connectedDevice == null || _commandCharacteristic == null) {
      _connectionStatusStreamController
          .add("Cihaz bağlı değil veya komut karakteristiği yok.");
      return;
    }
    try {
      await _commandCharacteristic!
          .write(utf8.encode("TOGGLE_BUZZER"), withoutResponse: true);
      if (kDebugMode) print("TOGGLE_BUZZER komutu gönderildi.");
    } catch (e) {
      if (kDebugMode) print("TOGGLE_BUZZER komutu gönderme hatası: $e");
      _connectionStatusStreamController
          .add("Hata: Buzzer komutu gönderilemedi.");
    }
  }

  Future<void> disconnectDevice() async {
    if (_connectedDevice != null) {
      _connectionStatusStreamController.add("Bağlantı kesiliyor...");
      await _connectionStateSubscription?.cancel();
      _connectionStateSubscription = null;
      await _gpsValueSubscription?.cancel();
      _gpsValueSubscription = null;
      try {
        await _connectedDevice!.disconnect();
      } catch (e) {
        if (kDebugMode) print("Disconnect hatası: $e");
      } finally {
        if (kDebugMode)
          print(
              "Cihaz bağlantısı (manuel) kesildi: ${_connectedDevice?.remoteId}");
        _connectedDevice = null;
        _gpsDataCharacteristic = null;
        _commandCharacteristic = null;
        _connectionStatusStreamController.add("Bağlantı Kesildi (Manuel)");
      }
    } else {
      _connectionStatusStreamController.add("Zaten bağlı cihaz yok.");
    }
  }

  bool isConnected() {
    return _connectedDevice != null && _connectedDevice!.isConnected;
  }

  void dispose() {
    if (kDebugMode) print("BluetoothService dispose ediliyor.");
    _connectionStateSubscription?.cancel();
    _gpsValueSubscription?.cancel();
    disconnectDevice();
    _gpsDataStreamController.close();
    _connectionStatusStreamController.close();
    // ADDED: Close the new stream controller
    _esp32EmergencyTriggerController.close();
  }
}

extension ListExtension<T> on List<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (var element in this) {
      if (test(element)) {
        return element;
      }
    }
    return null;
  }
}
