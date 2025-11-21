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
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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

  // Bluetooth camera variables
  bool _isBluetoothCameraConnected = false;
  String _bluetoothStatus = 'Disconnected';
  List<BluetoothDevice> devicesList = [];
  BluetoothDevice? connectedDevice;

  // Alert variables
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Firebase
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ⚠️ CHANGE THIS TO YOUR COMPUTER'S IP ADDRESS
  String backendUrl = 'http://10.86.66.10:5000/predict';

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
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        setState(() {
          _currentStatus = 'Camera permission denied';
        });
        return;
      }

      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _currentStatus = 'No camera found';
        });
        return;
      }

      final frontCamera = _cameras!.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

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

  // Connect Bluetooth Camera
  void _connectBluetoothCamera() async {
    if (_isBluetoothCameraConnected) {
      if (connectedDevice != null) {
        try {
          await connectedDevice!.disconnect();
          setState(() {
            _isBluetoothCameraConnected = false;
            _bluetoothStatus = 'Disconnected';
            connectedDevice = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bluetooth camera disconnected!'),
              backgroundColor: Colors.red,
            ),
          );
        } catch (e) {
          print("Error disconnecting: $e");
        }
      }
    } else {
      _showBluetoothDevicesDialog();
    }
  }

  void _showBluetoothDevicesDialog() async {
    if (await Permission.bluetooth.request().isGranted) {
      print("Scanning for Bluetooth devices...");

      setState(() {
        _bluetoothStatus = 'Scanning...';
      });

      devicesList.clear();

      FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

      var subscription = FlutterBluePlus.scanResults.listen((results) {
        setState(() {
          devicesList = results.map((r) => r.device).toList();
        });
      });

      await Future.delayed(const Duration(seconds: 5));
      FlutterBluePlus.stopScan();
      subscription.cancel();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select Bluetooth Device'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: devicesList.length,
              itemBuilder: (context, index) {
                final device = devicesList[index];
                return ListTile(
                  title: Text(device.name.isEmpty ? 'Unknown' : device.name),
                  subtitle: Text(device.id.id),
                  onTap: () {
                    _connectToDevice(device);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bluetooth permission denied')),
      );
    }
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() {
        connectedDevice = device;
        _isBluetoothCameraConnected = true;
        _bluetoothStatus = 'Connected: ${device.name}';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to ${device.name}!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _bluetoothStatus = 'Connection failed';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error connecting: $e')),
      );
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

  // Capture frame and send to backend - UPDATED FOR BASE64
  Future<void> _captureAndSendFrame() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      // Capture image
      final XFile image = await _cameraController!.takePicture();

      // Read image as bytes
      final bytes = await File(image.path).readAsBytes();

      // Convert to base64
      final base64Image = base64Encode(bytes);

      // Send to backend
      await _sendFrameToBackend(base64Image);
    } catch (e) {
      print('Error capturing frame: $e');
    }
  }

  // Send frame to Python backend - UPDATED FOR JSON
  Future<void> _sendFrameToBackend(String base64Image) async {
    try {
      final response = await http.post(
        Uri.parse(backendUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Image}),
      ).timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        _processMLResponse(jsonData);
      } else {
        print('Backend error: ${response.statusCode}');
        setState(() {
          _drowsinessStatus = 'Backend error';
        });
      }
    } catch (e) {
      print('Error sending to backend: $e');
      setState(() {
        _drowsinessStatus = 'Connection failed';
      });
    }
  }

  // Process ML response - UPDATED FOR KERAS BACKEND RESPONSE
  void _processMLResponse(Map<String, dynamic> response) {
    // Backend returns: {'is_drowsy': bool, 'confidence': float, 'alert_count': int}
    bool isDrowsy = response['is_drowsy'] ?? false;
    double confidence = response['confidence'] ?? 0.0;

    if (isDrowsy) {
      setState(() {
        _detectionCount++;
        _drowsinessStatus = 'Drowsy Detected! (${(confidence * 100).toStringAsFixed(1)}%)';
      });

      _triggerAlerts();
    } else {
      setState(() {
        _drowsinessStatus = 'Normal (${(confidence * 100).toStringAsFixed(1)}%)';
      });
    }
  }

  // Trigger alerts
  Future<void> _triggerAlerts() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = await _firestore.collection('users').doc(user.uid).get();
    final data = doc.data();

    bool soundAlert = data?['soundAlert'] ?? true;
    bool vibrationAlert = data?['vibrationAlert'] ?? true;
    bool smsAlert = data?['smsAlert'] ?? false;
    int threshold = data?['drowsinessThreshold'] ?? 3;

    if (soundAlert) {
      _playAlertSound();
    }

    if (vibrationAlert) {
      _triggerVibration();
    }

    if (smsAlert && _detectionCount >= threshold) {
      _sendEmergencySMS(data);
    }
  }

  // Play alert sound
  void _playAlertSound() async {
    try {
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
        'body':
        'ALERT: ${userData['fullName']} may be drowsy while driving! Detected $_detectionCount times.'
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
            const SizedBox(height: 12),

            // Bluetooth Webcam Connectivity Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.bluetooth, color: Colors.blue, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Webcam Connectivity',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _connectBluetoothCamera,
                          icon: Icon(
                            _isBluetoothCameraConnected
                                ? Icons.link_off
                                : Icons.link,
                            size: 18,
                            color: Colors.white,
                          ),
                          label: Text(
                            _isBluetoothCameraConnected
                                ? 'Disconnect'
                                : 'Connect',
                            style: TextStyle(fontSize: 13),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isBluetoothCameraConnected
                                ? Colors.red.shade400
                                : Colors.blue,
                            foregroundColor: Colors.white,
                            minimumSize: Size(70, 32),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Status: $_bluetoothStatus',
                      style: TextStyle(
                        fontSize: 13,
                        color: _isBluetoothCameraConnected
                            ? Colors.green
                            : Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_isBluetoothCameraConnected) ...[
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                Text('Camera feed will be shown here')),
                          );
                        },
                        icon: const Icon(Icons.camera_alt, size: 18),
                        label: const Text("Camera Feed"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          minimumSize: Size(110, 30),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

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
                    Text(
                      _currentStatus,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed:
                        _isCameraInitialized ? _toggleMonitoring : null,
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
                              _isMonitoring
                                  ? Icons.stop_circle
                                  : Icons.play_circle_filled,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _isMonitoring
                                  ? 'Stop Monitoring'
                                  : 'Start Monitoring',
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
