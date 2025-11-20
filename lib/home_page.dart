// home_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:url_launcher/url_launcher.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Camera variables
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isMonitoring = false;

  // Detection variables
  int _detectionCount = 0;
  String _currentStatus = 'Ready to start';
  String _drowsinessStatus = 'Normal';
  Timer? _captureTimer;

  // Alert variables
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Firebase
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Your Python Backend URL (You'll set this later)
  String backendUrl = 'http://192.168.29.210:5000/predict'; // Change this

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _captureTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // Initialize camera
  Future<void> _initializeCamera() async {
    try {
      // Request camera permission
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        setState(() {
          _currentStatus = 'Camera permission denied';
        });
        return;
      }

      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _currentStatus = 'No camera found';
        });
        return;
      }

      // Get front camera
      final frontCamera = _cameras!.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      // Initialize camera controller
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _currentStatus = 'Camera ready';
        });
      }
    } catch (e) {
      print('Error initializing camera: $e');
      setState(() {
        _currentStatus = 'Camera initialization failed';
      });
    }
  }

  // Toggle monitoring
  void _toggleMonitoring() {
    if (_isMonitoring) {
      _stopMonitoring();
    } else {
      _startMonitoring();
    }
  }

  // Start monitoring
  void _startMonitoring() {
    if (!_isCameraInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera not initialized')),
      );
      return;
    }

    setState(() {
      _isMonitoring = true;
      _currentStatus = 'Monitoring active...';
      _detectionCount = 0;
      _drowsinessStatus = 'Normal';
    });

    // Capture and send frames every 2 seconds
    _captureTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _captureAndSendFrame();
    });
  }

  // Stop monitoring
  void _stopMonitoring() {
    setState(() {
      _isMonitoring = false;
      _currentStatus = 'Monitoring stopped';
      _drowsinessStatus = 'Normal';
    });

    _captureTimer?.cancel();
  }

  // Capture frame and send to backend
  Future<void> _captureAndSendFrame() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      // Capture image
      final XFile image = await _cameraController!.takePicture();

      // Send to backend
      await _sendFrameToBackend(image.path);

    } catch (e) {
      print('Error capturing frame: $e');
    }
  }

  // Send frame to your Python backend
  Future<void> _sendFrameToBackend(String imagePath) async {
    try {
      // TODO: Replace with your actual backend URL
      // Example: 'http://192.168.1.100:5000/predict'

      var request = http.MultipartRequest('POST', Uri.parse(backendUrl));
      request.files.add(await http.MultipartFile.fromPath('image', imagePath));

      var response = await request.send();

      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final jsonData = json.decode(responseData);

        // Process response from your ML model
        _processMLResponse(jsonData);
      }

    } catch (e) {
      print('Error sending to backend: $e');
      // For testing without backend, use dummy response
      _testWithoutBackend();
    }
  }

  // Process ML response from your Python backend
  void _processMLResponse(Map<String, dynamic> response) {
    // Example response format from your backend:
    // { "drowsy": true, "ear": 0.15, "confidence": 0.95 }

    bool isDrowsy = response['drowsy'] ?? false;

    if (isDrowsy) {
      setState(() {
        _detectionCount++;
        _drowsinessStatus = 'Drowsy Detected!';
      });

      _triggerAlerts();
    } else {
      setState(() {
        _drowsinessStatus = 'Normal';
      });
    }
  }

  // Test mode (when backend is not ready)
  void _testWithoutBackend() {
    // Simulate detection for testing
    // Remove this when you connect to real backend
    setState(() {
      _drowsinessStatus = 'Testing mode (no backend)';
    });
  }

  // Trigger alerts
  Future<void> _triggerAlerts() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Get user settings
    final doc = await _firestore.collection('users').doc(user.uid).get();
    final data = doc.data();

    bool soundAlert = data?['soundAlert'] ?? true;
    bool vibrationAlert = data?['vibrationAlert'] ?? true;
    bool smsAlert = data?['smsAlert'] ?? false;
    int threshold = data?['drowsinessThreshold'] ?? 3;

    // Sound alert
    if (soundAlert) {
      _playAlertSound();
    }

    // Vibration alert
    if (vibrationAlert) {
      _triggerVibration();
    }

    // SMS alert (after threshold)
    if (smsAlert && _detectionCount >= threshold) {
      _sendEmergencySMS(data);
    }
  }

  // Play alert sound
  void _playAlertSound() async {
    try {
      // You can add your own alert sound file to assets
      // For now, using a system sound
      await _audioPlayer.play(AssetSource('alert_sound.mp3'));
    } catch (e) {
      print('Error playing sound: $e');
    }
  }

  // Trigger vibration
  void _triggerVibration() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 1000, amplitude: 255);
    }
  }

  // Send emergency SMS
  void _sendEmergencySMS(Map<String, dynamic>? userData) async {
    if (userData?['emergencyContact'] == null) return;

    final phone = userData!['emergencyContact']['phone'];
    final Uri smsUri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {
        'body': 'ALERT: ${userData['fullName']} may be drowsy while driving! Detected $_detectionCount times.'
      },
    );

    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF78C841),
        title: const Text('Driver Safety Monitor'),
        centerTitle: true,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Camera Preview Section
            if (_isCameraInitialized && _isMonitoring)
              Container(
                height: 300,
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _drowsinessStatus.contains('Drowsy')
                        ? Colors.red
                        : const Color(0xFF78C841),
                    width: 3,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: CameraPreview(_cameraController!),
                ),
              ),

            // Status Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Status Icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: _drowsinessStatus.contains('Drowsy')
                            ? Colors.red.withOpacity(0.1)
                            : const Color(0xFF78C841).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _drowsinessStatus.contains('Drowsy')
                            ? Icons.warning_amber_rounded
                            : _isMonitoring
                            ? Icons.visibility
                            : Icons.visibility_off,
                        size: 40,
                        color: _drowsinessStatus.contains('Drowsy')
                            ? Colors.red
                            : const Color(0xFF78C841),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Drowsiness Status
                    Text(
                      _drowsinessStatus,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _drowsinessStatus.contains('Drowsy')
                            ? Colors.red
                            : Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Current Status
                    Text(
                      _currentStatus,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Start/Stop Button
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: _isCameraInitialized ? _toggleMonitoring : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isMonitoring
                              ? Colors.red.shade400
                              : const Color(0xFF78C841),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isMonitoring ? Icons.stop_circle : Icons.play_circle_filled,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _isMonitoring ? 'Stop Monitoring' : 'Start Monitoring',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Stats Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      title: 'Detections',
                      value: '$_detectionCount',
                      icon: Icons.warning_amber_rounded,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      title: 'Status',
                      value: _isMonitoring ? 'Active' : 'Inactive',
                      icon: Icons.info_outline,
                      color: _isMonitoring ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 32,
            color: color,
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
