import 'package:flutter/material.dart';

class NavBar extends StatelessWidget {
  final int selectedIndex;
  const NavBar({Key? key, required this.selectedIndex}) : super(key: key);

  void _onItemTapped(BuildContext context, int index) {
    if (index == selectedIndex) return; // Aynı sayfadaysa tekrar yönlendirme
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/questions');
        break;
      case 1:
        Navigator.pushReplacementNamed(context, '/home');
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: selectedIndex,
      onTap: (index) => _onItemTapped(context, index),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.quiz, size: 30),
          label: 'Test',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.home, size: 30),
          label: 'Ana Sayfa',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person, size: 30),
          label: 'Profil',
        ),
      ],
      selectedItemColor: Colors.green,
      backgroundColor: Colors.white24,
      selectedFontSize: 16,
      unselectedFontSize: 14,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold),
      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.bold),
    );
  }
}
