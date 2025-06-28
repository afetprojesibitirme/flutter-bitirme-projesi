import 'dart:async';
import 'dart:convert'; // json.decode, utf8.decode için
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

const String esp32DeviceName = "ESP32_GPS_Tracker";
const String serviceUuidString = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String characteristicUuidGpsDataString = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
const String characteristicUuidCommandString = "f27b53ad-39c1-4c60-b1ff-ff97c2af3788";

class BluetoothService {
  fbp.BluetoothDevice? _connectedDevice;
  fbp.BluetoothCharacteristic? _gpsDataCharacteristic;
  fbp.BluetoothCharacteristic? _commandCharacteristic;
  StreamSubscription<fbp.BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<int>>? _gpsValueSubscription;

  final StreamController<Map<String, dynamic>> _gpsDataStreamController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get gpsDataStream => _gpsDataStreamController.stream;

  final StreamController<String> _connectionStatusStreamController = StreamController.broadcast();
  Stream<String> get connectionStatusStream => _connectionStatusStreamController.stream;

  // YENİ: ESP32 acil durum butonu için StreamController
  final StreamController<Map<String, dynamic>> _esp32EmergencyTriggerController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get esp32EmergencyTriggerStream => _esp32EmergencyTriggerController.stream;

  BluetoothService() {
    fbp.FlutterBluePlus.adapterState.listen((state) {
      if (kDebugMode) print("Bluetooth Adaptör Durumu: $state");
      if (state == fbp.BluetoothAdapterState.on) {
        _connectionStatusStreamController.add("Bluetooth Açık, Cihaz Aranıyor...");
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
      List<fbp.BluetoothDevice> connectedDevices = await fbp.FlutterBluePlus.connectedDevices;
      if (connectedDevices.isNotEmpty) {
        fbp.BluetoothDevice? esp32 = connectedDevices.firstWhereOrNull((d) => d.platformName == esp32DeviceName);
        if (esp32 != null) {
          _connectedDevice = esp32;
          await _discoverServicesAndCharacteristics();
          _connectionStatusStreamController.add("Önceden Bağlı: ${esp32.platformName}");
          return;
        }
      }
      _connectionStatusStreamController.add("Cihaz Aranıyor...");
      scanAndConnect();
    } catch (e) {
      if (kDebugMode) print("Initial connection check error: $e");
      _connectionStatusStreamController.add("Hata: Başlangıç Bağlantı Kontrolü");
    }
  }

  Future<void> scanAndConnect() async {
    if (await fbp.FlutterBluePlus.isScanning.first) {
      if (kDebugMode) print("Zaten taranıyor.");
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
            if (r.device.platformName == esp32DeviceName) {
              fbp.FlutterBluePlus.stopScan();
              _connectedDevice = r.device;
              _connectionStatusStreamController.add("Cihaz Bulundu: ${r.device.platformName}. Bağlanılıyor...");
              try {
                await _connectedDevice!.connect(timeout: const Duration(seconds: 10), autoConnect: false);
                await _discoverServicesAndCharacteristics();
                _connectionStatusStreamController.add("Cihaz Bağlandı: ${r.device.platformName}");
                _listenToConnectionState();
                requestGpsDataFromDevice();
              } catch (e) {
                if (kDebugMode) print("Bağlantı Hatası: $e");
                _connectionStatusStreamController.add("Bağlantı Hatası: $e");
                _connectedDevice = null;
                Future.delayed(const Duration(seconds: 2), () => scanAndConnect());
              }
              return;
            }
          }
        },
      );

      fbp.FlutterBluePlus.cancelWhenScanComplete(subscription);
      await fbp.FlutterBluePlus.startScan(withNames: [esp32DeviceName], timeout: const Duration(seconds: 15));
      if (_connectedDevice == null) {
        _connectionStatusStreamController.add("Cihaz bulunamadı, tekrar deneniyor...");
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
      List<fbp.BluetoothService> services = await _connectedDevice!.discoverServices();
      for (var service in services) {
        if (service.uuid.toString() == serviceUuidString) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == characteristicUuidGpsDataString) {
              _gpsDataCharacteristic = characteristic;
              if (characteristic.properties.notify || characteristic.properties.indicate) {
                await characteristic.setNotifyValue(true);
                _gpsValueSubscription = characteristic.lastValueStream.listen((value) {
                  if (value.isNotEmpty) {
                    try {
                      String jsonString = utf8.decode(value);
                      if (kDebugMode) print("Alınan GPS JSON: $jsonString");
                      Map<String, dynamic> gpsData = json.decode(jsonString);
                      
                      // DEĞİŞTİ: ESP32 acil durum sinyalini kontrol et
                      if (gpsData['is_esp32_emergency'] == true) {
                        if (kDebugMode) print("ESP32 Acil Durum Sinyali Alındı!");
                        _esp32EmergencyTriggerController.add(gpsData);
                      }
                      
                      _gpsDataStreamController.add(gpsData);
                    } catch (e) {
                      if (kDebugMode) print("GPS JSON parse hatası: $e, Veri: ${utf8.decode(value)}");
                    }
                  }
                });
                _connectionStatusStreamController.add("Cihaz hazır: GPS karakteristik alındı.");
              }
            } else if (characteristic.uuid.toString() == characteristicUuidCommandString) {
              _commandCharacteristic = characteristic;
              _connectionStatusStreamController.add("Cihaz hazır: Komut karakteristik alındı.");
            }
          }
        }
      }
      if (_gpsDataCharacteristic == null || _commandCharacteristic == null) {
        _connectionStatusStreamController.add("Uyarı: Gerekli karakteristikler bulunamadı.");
        disconnectDevice();
      }
    } catch (e) {
      if (kDebugMode) print("Servis Keşif Hatası: $e");
      _connectionStatusStreamController.add("Hata: Servis Keşfi");
      disconnectDevice();
    }
  }

  void _listenToConnectionState() {
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = _connectedDevice?.connectionState.listen((state) {
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
  
  // YENİ: ESP32'ye yön komutu gönderen fonksiyon
  Future<void> sendDirectionToDevice(double bearing) async {
    if (!isConnected() || _commandCharacteristic == null) {
      if (kDebugMode) print("Yön gönderilemedi: Cihaz bağlı değil veya komut karakteristiği yok.");
      return;
    }
    try {
      final command = "DIR:${bearing.toStringAsFixed(1)}";
      await _commandCharacteristic!.write(utf8.encode(command), withoutResponse: true);
      if (kDebugMode) print("Yön komutu gönderildi: $command");
    } catch (e) {
      if (kDebugMode) print("Yön komutu gönderme hatası: $e");
    }
  }

  Future<void> requestGpsDataFromDevice() async {
    if (!isConnected() || _commandCharacteristic == null) return;
    try {
      await _commandCharacteristic!.write(utf8.encode("REQUEST_GPS"), withoutResponse: true);
      if (kDebugMode) print("REQUEST_GPS komutu gönderildi.");
    } catch (e) {
      if (kDebugMode) print("REQUEST_GPS gönderme hatası: $e");
    }
  }

  Future<void> toggleBuzzerOnDevice() async {
    if (!isConnected() || _commandCharacteristic == null) return;
    try {
      await _commandCharacteristic!.write(utf8.encode("TOGGLE_BUZZER"), withoutResponse: true);
      if (kDebugMode) print("TOGGLE_BUZZER komutu gönderildi.");
    } catch (e) {
      if (kDebugMode) print("TOGGLE_BUZZER gönderme hatası: $e");
    }
  }

  Future<void> disconnectDevice() async {
    if (_connectedDevice != null) {
      await _connectionStateSubscription?.cancel();
      _connectionStateSubscription = null;
      await _gpsValueSubscription?.cancel();
      _gpsValueSubscription = null;
      try {
        await _connectedDevice!.disconnect();
      } catch (e) {
        if (kDebugMode) print("Disconnect hatası: $e");
      } finally {
        _connectedDevice = null;
        _connectionStatusStreamController.add("Bağlantı Kesildi (Manuel)");
      }
    }
  }

  bool isConnected() {
    return _connectedDevice != null && _connectedDevice!.isConnected;
  }

  void dispose() {
    _connectionStateSubscription?.cancel();
    _gpsValueSubscription?.cancel();
    _esp32EmergencyTriggerController.close(); // YENİ
    disconnectDevice();
    _gpsDataStreamController.close();
    _connectionStatusStreamController.close();
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