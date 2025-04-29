import 'package:bitirme_projesi/navbar.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _editMode = false;

  // Profil bilgileri
  String adSoyad = '';
  String yas = '';
  String kanGrubu = '';
  String hastaliklar = '';

  // Controllerlar
  late TextEditingController adSoyadController;
  late TextEditingController yasController;
  late TextEditingController kanGrubuController;
  late TextEditingController hastaliklarController;

  @override
  void initState() {
    super.initState();
    adSoyadController = TextEditingController();
    yasController = TextEditingController();
    kanGrubuController = TextEditingController();
    hastaliklarController = TextEditingController();
    _loadProfile();
  }

  @override
  void dispose() {
    adSoyadController.dispose();
    yasController.dispose();
    kanGrubuController.dispose();
    hastaliklarController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      adSoyad = prefs.getString('adSoyad') ?? '';
      yas = prefs.getString('yas') ?? '';
      kanGrubu = prefs.getString('kanGrubu') ?? '';
      hastaliklar = prefs.getString('hastaliklar') ?? '';
      adSoyadController.text = adSoyad;
      yasController.text = yas;
      kanGrubuController.text = kanGrubu;
      hastaliklarController.text = hastaliklar;
    });
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('adSoyad', adSoyadController.text);
    await prefs.setString('yas', yasController.text);
    await prefs.setString('kanGrubu', kanGrubuController.text);
    await prefs.setString('hastaliklar', hastaliklarController.text);
    setState(() {
      adSoyad = adSoyadController.text;
      yas = yasController.text;
      kanGrubu = kanGrubuController.text;
      hastaliklar = hastaliklarController.text;
      _editMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Bilgiler kaydedildi!'), backgroundColor: Colors.green),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    required bool enabled,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey[400]?.withOpacity(enabled ? 0.3 : 0.5),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF444444),
      body: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.92,
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF6D6D6D),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      'DETAYLI BİLGİLER',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _buildField(
                  label: 'Ad Soyad :',
                  controller: adSoyadController,
                  enabled: _editMode,
                ),
                const SizedBox(height: 16),
                _buildField(
                  label: 'Yaş :',
                  controller: yasController,
                  enabled: _editMode,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                _buildField(
                  label: 'Kan Grubu :',
                  controller: kanGrubuController,
                  enabled: _editMode,
                ),
                const SizedBox(height: 16),
                _buildField(
                  label: 'Hastalıklar :',
                  controller: hastaliklarController,
                  enabled: _editMode,
                  maxLines: 2,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_editMode) {
                        _saveProfile();
                      } else {
                        setState(() {
                          _editMode = true;
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _editMode ? Colors.green : Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      _editMode ? 'Kaydet' : 'Düzenle',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const NavBar(selectedIndex: 2),
    );
  }
}
