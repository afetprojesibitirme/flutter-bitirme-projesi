import 'package:bitirme_projesi/navbar.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final EmergencyServices _services = EmergencyServices();

  Future<void> _handleEmergencyButton() async {
    try {
      await _services.saveEmergencyLocation();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Konumunuz acil durum ekiplerine iletildi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _call112() async {
    final Uri url = Uri.parse('tel:112');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('112 aranamıyor'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _findNearestGatheringArea() async {
    try {
      final nearestArea = await _services.findNearestGatheringArea();
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('En Yakın Toplanma Alanı'),
            content: Text(
              'Koordinatlar: ${nearestArea['coordinates']}\nUzaklık: ${nearestArea['distance']} km',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final buttonWidth = screenWidth * 0.8;
    final buttonHeight = screenHeight * 0.09;
    final minButtonWidth = 300.0;
    final minButtonHeight = 65.0;

    final finalButtonWidth =
        buttonWidth > minButtonWidth ? buttonWidth : minButtonWidth;
    final finalButtonHeight =
        buttonHeight > minButtonHeight ? buttonHeight : minButtonHeight;

    return Scaffold(
      backgroundColor: Colors.white12,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ACİL butonu
                  GestureDetector(
                    onTap: _handleEmergencyButton,
                    child: Container(
                      width: screenWidth * 0.6,
                      height: screenWidth * 0.6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        color: Colors.red,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.3),
                            spreadRadius: 3,
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'ACİL',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: screenWidth * 0.12,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.3),
                                offset: const Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.04),

                  // 112 Butonu
                  Container(
                    width: finalButtonWidth,
                    height: finalButtonHeight,
                    child: TextButton.icon(
                      onPressed: _call112,
                      icon: Icon(
                        Icons.phone,
                        color: Colors.white,
                        size: finalButtonHeight * 0.6,
                      ),
                      label: Text(
                        '112',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: finalButtonHeight * 0.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.green,
                        minimumSize: Size(finalButtonWidth, finalButtonHeight),
                        padding: EdgeInsets.symmetric(
                            horizontal: finalButtonWidth * 0.07),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.04),

                  // Toplanma Alanı Butonu
                  Container(
                    width: finalButtonWidth,
                    height: finalButtonHeight,
                    child: TextButton(
                      onPressed: _findNearestGatheringArea,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.orange,
                        minimumSize: Size(finalButtonWidth, finalButtonHeight),
                        padding: EdgeInsets.symmetric(
                            horizontal: finalButtonWidth * 0.05),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: Text(
                        'Toplanma Alanı Bul',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: const NavBar(selectedIndex: 1),
    );
  }
}
