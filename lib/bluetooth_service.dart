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

  BluetoothService() {
    // Uygulama başladığında Bluetooth durumunu dinlemeye başla
    fbp.FlutterBluePlus.adapterState.listen((state) {
      if (kDebugMode) print("Bluetooth Adaptör Durumu: $state");
      if (state == fbp.BluetoothAdapterState.on) {
        _connectionStatusStreamController
            .add("Bluetooth Açık, Cihaz Aranıyor...");
        scanAndConnect();
      } else {
        _connectionStatusStreamController.add("Bluetooth Kapalı: $state");
        disconnectDevice(); // Bluetooth kapalıysa bağlantıyı kes
      }
    });

    // Zaten bağlı cihaz varsa durumu kontrol et
    _checkInitialConnection();
  }

  // Uygulama başlangıcında veya yeniden başlatıldığında önceden bağlı cihazı kontrol eder
  Future<void> _checkInitialConnection() async {
    try {
      List<fbp.BluetoothDevice> connectedDevices =
          await fbp.FlutterBluePlus.connectedDevices;
      if (connectedDevices.isNotEmpty) {
        // En son bağlandığımız cihazı bulmaya çalış (ismiyle)
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
      scanAndConnect(); // Bağlı cihaz yoksa tara ve bağlan
    } catch (e) {
      if (kDebugMode) print("Initial connection check error: $e");
      _connectionStatusStreamController
          .add("Hata: Başlangıç Bağlantı Kontrolü");
    }
  }

  // Bluetooth cihazlarını tarar ve ESP32 cihazına bağlanır
  Future<void> scanAndConnect() async {
    // isScanning.value yerine await isScanning.first kullanıldı
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
      // Tarama sonuçlarını dinle
      var subscription = fbp.FlutterBluePlus.scanResults.listen(
        (results) async {
          for (fbp.ScanResult r in results) {
            if (kDebugMode)
              print(
                  'Bulunan Cihaz: ${r.device.platformName} - ${r.device.remoteId}');
            if (r.device.platformName == esp32DeviceName) {
              fbp.FlutterBluePlus
                  .stopScan(); // Cihaz bulunduğunda taramayı durdur
              _connectedDevice = r.device;
              _connectionStatusStreamController.add(
                  "Cihaz Bulundu: ${r.device.platformName}. Bağlanılıyor...");
              try {
                await _connectedDevice!.connect(
                  timeout: const Duration(seconds: 10),
                  autoConnect:
                      false, // İlk bağlantı için false, manuel kontrol daha iyi
                );
                await _discoverServicesAndCharacteristics(); // Servis ve karakteristikleri keşfet
                _connectionStatusStreamController
                    .add("Cihaz Bağlandı: ${r.device.platformName}");
                _listenToConnectionState(); // Bağlantı durumunu dinle
                requestGpsDataFromDevice(); // Bağlandıktan sonra hemen veri iste
              } catch (e) {
                if (kDebugMode) print("Bağlantı Hatası: $e");
                _connectionStatusStreamController.add("Bağlantı Hatası: $e");
                _connectedDevice = null;
                // Bağlantı başarısız olursa tekrar tara (küçük bir gecikme ile)
                Future.delayed(
                    const Duration(seconds: 2), () => scanAndConnect());
              }
              return; // Cihaz bulunduğunda döngüden çık
            }
          }
        },
      );

      fbp.FlutterBluePlus.cancelWhenScanComplete(
          subscription); // Tarama bitince aboneliği iptal et
      await fbp.FlutterBluePlus.startScan(
        withNames: [
          esp32DeviceName
        ], // Sadece belirlediğimiz isimdeki cihazı tara
        timeout: const Duration(seconds: 15),
      );
      // Tarama bittikten sonra hala bağlı cihaz yoksa
      if (_connectedDevice == null) {
        _connectionStatusStreamController
            .add("Cihaz bulunamadı, tekrar deneniyor...");
        Future.delayed(const Duration(seconds: 2),
            () => scanAndConnect()); // Cihaz bulunamazsa tekrar dene
      }
    } catch (e) {
      if (kDebugMode) print("Tarama Hatası: $e");
      _connectionStatusStreamController.add("Tarama Hatası: $e");
      // Hata durumunda tarama devam ediyorsa durdur
      if (await fbp.FlutterBluePlus.isScanning.first) {
        // isScanning.value yerine await isScanning.first kullanıldı
        fbp.FlutterBluePlus.stopScan();
      }
    }
  }

  // Bağlı cihazın servislerini ve karakteristiklerini keşfeder
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
              // Notify veya Indicate özelliğini etkinleştir
              if (characteristic.properties.notify ||
                  characteristic.properties.indicate) {
                await characteristic.setNotifyValue(true);
                _gpsValueSubscription =
                    characteristic.lastValueStream.listen((value) {
                  if (value.isNotEmpty) {
                    try {
                      String jsonString = utf8.decode(value);
                      if (kDebugMode) print("Alınan GPS JSON: $jsonString");
                      Map<String, dynamic> gpsData = json.decode(jsonString);
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
      // Eğer gerekli tüm karakteristikler bulunamadıysa bir uyarı ver
      if (_gpsDataCharacteristic == null || _commandCharacteristic == null) {
        _connectionStatusStreamController
            .add("Uyarı: Bazı karakteristikler bulunamadı.");
        disconnectDevice(); // Eksik karakteristik varsa bağlantıyı kes ve tekrar dene
      }
    } catch (e) {
      if (kDebugMode) print("Servis ve Karakteristik Keşif Hatası: $e");
      _connectionStatusStreamController.add("Hata: Servis/Karakteristik Keşfi");
      disconnectDevice(); // Hata durumunda bağlantıyı kes
    }
  }

  // Cihazın bağlantı durumunu dinler (kopma, yeniden bağlanma vb.)
  void _listenToConnectionState() {
    _connectionStateSubscription?.cancel(); // Önceki aboneliği iptal et
    _connectionStateSubscription =
        _connectedDevice?.connectionState.listen((state) {
      if (kDebugMode) print("Bağlantı Durumu Değişti: $state");
      if (state == fbp.BluetoothConnectionState.disconnected) {
        _connectionStatusStreamController.add("Bağlantı Kesildi.");
        _connectedDevice = null;
        _gpsDataCharacteristic = null;
        _commandCharacteristic = null;
        _gpsValueSubscription?.cancel(); // GPS veri akışını da durdur
        _gpsValueSubscription = null;
        // Otomatik yeniden bağlanma:
        Future.delayed(const Duration(seconds: 2), () {
          if (!isConnected()) {
            // Sadece gerçekten bağlı değilsek tekrar tara
            scanAndConnect();
          }
        });
      } else if (state == fbp.BluetoothConnectionState.connected) {
        _connectionStatusStreamController.add("Yeniden Bağlandı.");
        // Bağlantı yeniden sağlandığında servisleri tekrar keşfet
        _discoverServicesAndCharacteristics();
      }
    });
  }

  // ESP32'den GPS verisi isteği gönderir
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

  // ESP32'deki buzzer'ı açma/kapama komutu gönderir
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

  // Bluetooth bağlantısını keser
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

  // Cihazın bağlı olup olmadığını kontrol eder
  bool isConnected() {
    return _connectedDevice != null && _connectedDevice!.isConnected;
  }

  // StreamController'ları kapatır ve kaynakları serbest bırakır
  void dispose() {
    if (kDebugMode) print("BluetoothService dispose ediliyor.");
    _connectionStateSubscription?.cancel();
    _gpsValueSubscription?.cancel();
    disconnectDevice(); // Kaynakları temizlemeden önce bağlantıyı kes
    _gpsDataStreamController.close();
    _connectionStatusStreamController.close();
  }
}

// Utility extension for List to find the first element or return null
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
