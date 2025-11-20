// main_navigation.dart
import 'package:flutter/material.dart';
import 'account_page.dart';
import 'home_page.dart';
import 'settings_page.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({Key? key}) : super(key: key);

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 1; // Start with Home page (middle tab)

  // List of pages - Order: Account, Home, Settings
  final List<Widget> _pages = [
    const AccountPage(),  // Index 0 - Left tab
    const HomePage(),     // Index 1 - Middle tab (default)
    const SettingsPage(), // Index 2 - Right tab
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex], // Display current page based on selected tab

      // Bottom Navigation Bar
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index; // Change page when tab is tapped
          });
        },
        selectedItemColor: const Color(0xFF78C841), // Green color when selected
        unselectedItemColor: Colors.grey, // Grey when not selected
        backgroundColor: Colors.white,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        items: const [
          // Left tab - Account
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Account',
          ),
          // Middle tab - Home
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          // Right tab - Settings
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
