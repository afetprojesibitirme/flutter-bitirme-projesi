// lib/emergency_display_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart'; // kDebugMode için eklendi
import 'navbar.dart'; // Added NavBar import

class EmergencyDisplayPage extends StatelessWidget {
  final DocumentSnapshot emergencyDataSnapshot;

  const EmergencyDisplayPage({super.key, required this.emergencyDataSnapshot});

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'Bilinmiyor';
    try {
      return DateFormat('dd MMMM yyyy, HH:mm:ss', 'tr_TR')
          .format(timestamp.toDate());
    } catch (e) {
      if (kDebugMode)
        print("Tarih formatlama hatası: $e"); // kDebugMode doğru import edildi
      return timestamp.toDate().toLocal().toString().substring(0, 19);
    }
  }

  Widget _buildInfoRow(BuildContext context, String label, String? value,
      {IconData? icon, Color valueColor = Colors.white70}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon,
                color: Theme.of(context).colorScheme.secondary, size: 20),
            const SizedBox(width: 8)
          ],
          Expanded(
            flex: 4,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value ?? 'Bilinmiyor',
              style: TextStyle(
                color: valueColor,
                fontSize: 16,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = emergencyDataSnapshot.data() as Map<String, dynamic>;
    final GeoPoint location = data['location'];
    final Timestamp timestamp = data['timestamp'];

    return Scaffold(
      backgroundColor: Colors.white12,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 60, left: 32, right: 32, bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: const Color(0xFF6D6D6D),
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
                      'Konum Bilgileri',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Divider(height: 20, thickness: 1, color: Colors.white24),
                    _buildInfoRow(
                        context, 'Enlem', location.latitude.toStringAsFixed(6),
                        icon: Icons.location_on_outlined,
                        valueColor: Colors.white70),
                    _buildInfoRow(context, 'Boylam',
                        location.longitude.toStringAsFixed(6),
                        icon: Icons.location_on_outlined,
                        valueColor: Colors.white70),
                    _buildInfoRow(
                        context, 'Zaman Damgası', _formatTimestamp(timestamp),
                        icon: Icons.access_time,
                        valueColor: Colors.white70),
                    _buildInfoRow(context, 'Kaynak', data['source'] as String?,
                        icon: Icons.devices_other,
                        valueColor: Colors.white70),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (data['esp32_distance_to_area_m'] != null)
              Card(
                color: const Color(0xFF6D6D6D),
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
                        'Toplanma Alanı Bilgileri (ESP32 Konumuna Göre)',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Divider(height: 20, thickness: 1, color: Colors.white24),
                      _buildInfoRow(context, '  Alan Adı',
                          data['esp32_nearest_area_name'] as String?,
                          icon: Icons.meeting_room_outlined,
                          valueColor: Colors.white70),
                      _buildInfoRow(
                          context,
                          '  Alanda Mesafe',
                          data['esp32_distance_to_area_m'] != null
                              ? '${(data['esp32_distance_to_area_m'] as num).toStringAsFixed(1)} m'
                              : null,
                          icon: Icons.space_dashboard_outlined,
                          valueColor: Colors.white70),
                      _buildInfoRow(context, '  Alanda Yön',
                          data['esp32_direction_to_area'] as String?,
                          icon: Icons.navigation_outlined,
                          valueColor: Colors.white70),
                      _buildInfoRow(context, '  Uydu Sayısı',
                          (data['esp32_satellites'] as int?)?.toString(),
                          icon: Icons.satellite_alt_outlined,
                          valueColor: Colors.white70),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              label: const Text('Anasayfaya Dön'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.popUntil(context, (route) => route.isFirst);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      bottomNavigationBar: const NavBar(selectedIndex: 1),
    );
  }
}
