
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'edit_detail_page.dart'; // Import the edit page

class AccountPage extends StatefulWidget {
  const AccountPage({Key? key}) : super(key: key);

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late User? currentUser;
  Map<String, dynamic>? userData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      currentUser = _auth.currentUser;
      if (currentUser != null) {
        final doc = await _firestore.collection('users').doc(currentUser!.uid).get();
        if (doc.exists) {
          setState(() {
            userData = doc.data();
            isLoading = false;
          });
        } else {
          setState(() {
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print("Error loading user data: $e");
      setState(() {
        isLoading = false;
      });
    }
  }

  // Navigate to edit page
  Future<void> _navigateToEdit({
    required String title,
    required String field,
    String? currentValue,
    String? currentValue2,
  }) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditDetailPage(
          title: title,
          field: field,
          currentValue: currentValue,
          currentValue2: currentValue2,
        ),
      ),
    );

    // Refresh data if something was saved
    if (result == true) {
      _loadUserData();
    }
  }

  Future<void> _sendEmergencySMS() async {
    if (userData != null && userData!['emergencyContact'] != null) {
      final emergencyPhone = userData!['emergencyContact']['phone'];
      final message = 'Emergency Alert! Please contact ${userData!['fullName']} immediately.';

      final Uri smsUri = Uri(
        scheme: 'sms',
        path: emergencyPhone,
        queryParameters: {'body': message},
      );

      try {
        if (await canLaunchUrl(smsUri)) {
          await launchUrl(smsUri);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('SMS app not available')),
            );
          }
        }
      } catch (e) {
        print('Error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FB),
      body: Stack(
        children: [
          // Decorative pattern (behind content)
          _buildDecorativePattern(),

          // Main content
          SafeArea(
            child: isLoading
                ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF78C841),
              ),
            )
                : SingleChildScrollView(
              child: Column(
                children: [
                  // Clean Profile Card
                  Stack(
                    children: [
                      // Card
                      Container(
                        margin: const EdgeInsets.only(top: 60),
                        padding: const EdgeInsets.only(
                            top: 70, bottom: 20, left: 24, right: 24),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Color(0xFF78C841),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Name and email
                            Text(
                              userData?['fullName'] ??
                                  currentUser?.displayName ??
                                  'User',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF232323),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              userData?['email'] ??
                                  currentUser?.email ??
                                  '',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Profile avatar
                      Positioned(
                        top: 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.lightGreenAccent,
                                width: 4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: currentUser?.photoURL != null
                                  ? Image.network(
                                currentUser!.photoURL!,
                                fit: BoxFit.cover,
                              )
                                  : Container(
                                color: Colors.white,
                                child: Center(
                                  child: Text(
                                    (userData?['fullName'] ?? 'U')[0]
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF7A7A7A),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),

                  // Main menu section (NOW CLICKABLE!)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                            offset: Offset(0, 2)),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildMenuItem(
                          icon: Icons.location_on_outlined,
                          title: 'My Address',
                          subtitle: userData?['location'] ?? 'Not set',
                          onTap: () => _navigateToEdit(
                            title: 'My Address',
                            field: 'location',
                            currentValue: userData?['location'],
                          ),
                        ),
                        _buildDivider(),
                        _buildMenuItem(
                          icon: Icons.email_outlined,
                          title: 'Email',
                          subtitle: userData?['email'] ?? 'Not set',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                  Text('Email cannot be changed')),
                            );
                          },
                        ),
                        _buildDivider(),
                        _buildMenuItem(
                          icon: Icons.phone_outlined,
                          title: 'Phone Number',
                          subtitle: userData?['phoneNumber'] ?? 'Not set',
                          onTap: () => _navigateToEdit(
                            title: 'Phone Number',
                            field: 'phoneNumber',
                            currentValue: userData?['phoneNumber'],
                          ),
                        ),
                        _buildDivider(),
                        _buildMenuItem(
                          icon: Icons.language_outlined,
                          title: 'Language',
                          subtitle: userData?['language'] ?? 'English',
                          onTap: () => _navigateToEdit(
                            title: 'Language',
                            field: 'language',
                            currentValue: userData?['language'],
                          ),
                        ),
                        _buildDivider(),
                        _buildMenuItem(
                          icon: Icons.add_call,
                          title: 'Emergency contact',
                          subtitle: userData?['emergencyContact'] != null
                              ? '${userData!['emergencyContact']['name']} - ${userData!['emergencyContact']['phone']}'
                              : 'Not set',
                          onTap: () => _navigateToEdit(
                            title: 'Emergency Contact',
                            field: 'emergencyContact',
                            currentValue:
                            userData?['emergencyContact']?['name'],
                            currentValue2:
                            userData?['emergencyContact']?['phone'],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Emergency Contact Section
                  if (userData != null &&
                      userData!['emergencyContact'] != null)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.emergency_outlined,
                                  color: Colors.red.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Emergency Contact',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Name: ${userData!['emergencyContact']['name']}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Phone: ${userData!['emergencyContact']['phone']}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _sendEmergencySMS,
                              icon: const Icon(Icons.sms),
                              label: const Text('Send Emergency SMS'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: Colors.grey.shade700, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: Colors.grey.shade200,
      indent: 56,
    );
  }

  // Decorative pattern widget
  Widget _buildDecorativePattern() {
    return Stack(
      children: [
        // Large circle - top left
        Positioned(
          top: -50,
          left: -60,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF78C841).withOpacity(0.9),
                width: 2,
              ),
            ),
          ),
        ),
        // Medium circle - top left inside
        Positioned(
          top: 10,
          left: -20,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF78C841).withOpacity(0.4),
            ),
          ),
        ),
        // Small circle - top right
        Positioned(
          top: 30,
          right: -30,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF78C841).withOpacity(0.9),
                width: 1.5,
              ),
            ),
          ),
        ),
        // Bottom right pattern
        Positioned(
          bottom: -40,
          right: -50,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF78C841).withOpacity(0.9),
                width: 2,
              ),
            ),
          ),
        ),
        // Medium circle - bottom right inside
        Positioned(
          bottom: 20,
          right: 10,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF78C841).withOpacity(0.5),
            ),
          ),
        ),
      ],
    );
  }
}
