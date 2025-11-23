import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ml_model_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MLModelService _mlModelService = MLModelService();
  bool _isModelLoaded = false;
  bool _isModelLoading = true;
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isMonitoring = false;

  int _detectionCount = 0;
  String _currentStatus = 'Initializing...';
  String _drowsinessStatus = 'Normal';
  Timer? _captureTimer;

  bool _soundAlert = true;
  bool _vibrationAlert = true;
  bool _smsAlert = false;
  int _drowsinessThreshold = 3;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Bluetooth webcam variables
  bool _isBluetoothCameraConnected = false;
  String _bluetoothStatus = 'Disconnected';
  List<BluetoothDevice> devicesList = [];
  BluetoothDevice? connectedDevice;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Initialize both camera and model
    await Future.wait([
      _initializeCamera(),
      _loadModel(),
    ]);

    // Load user settings
    await _loadUserSettings();
  }

  Future<void> _loadModel() async {
    try {
      setState(() {
        _currentStatus = 'Loading AI model...';
        _isModelLoading = true;
      });

      // Add timeout to prevent hanging
      await _mlModelService.loadModel().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('⚠️ Model loading timed out - using fallback mode');
          throw TimeoutException('Model loading timed out');
        },
      );

      if (mounted) {
        setState(() {
          _isModelLoaded = true;
          _isModelLoading = false;
          _currentStatus = _isCameraInitialized ? 'Ready to start' : 'Waiting for camera...';
        });
        print("✅ TFLite models loaded for inference.");
      }
    } catch (e) {
      print('⚠️ Error loading model: $e');
      // Set model as loaded anyway to allow testing without model
      if (mounted) {
        setState(() {
          _isModelLoaded = true; // Enable button anyway
          _isModelLoading = false;
          _currentStatus = _isCameraInitialized ? 'Ready to start (No AI)' : 'Waiting for camera...';
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _captureTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _captureAndRunInference() async {
    if (!_isCameraInitialized) {
      print('Camera not initialized');
      return;
    }

    try {
      final XFile image = await _cameraController!.takePicture();

      // If model is not loaded, just show camera is working
      if (!_isModelLoaded) {
        print('📸 Camera captured image - Model not available for inference');
        setState(() {
          _drowsinessStatus = 'Demo Mode';
        });
        return;
      }

      final Uint8List bytes = await File(image.path).readAsBytes();

      List<double> inputTensor = _mlModelService.preprocessCameraFile(bytes);
      final prediction = await _mlModelService.runPrediction(inputTensor);

      print("Eye closed: ${prediction['eye_closed']} (scores: ${prediction['eye_confidence']})");
      print("Yawn detected: ${prediction['yawn_detected']} (scores: ${prediction['yawn_confidence']})");

      bool isDrowsy = prediction['eye_closed'] || prediction['yawn_detected'];
      setState(() {
        _drowsinessStatus = isDrowsy ? 'Drowsy Detected!' : 'Normal';
        if (isDrowsy) _detectionCount++;
      });
      if (isDrowsy) _triggerAlerts();
    } catch (e) {
      print('Error in inference: $e');
    }
  }

  Future<void> _loadUserSettings() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final data = doc.data();
          if (mounted) {
            setState(() {
              _soundAlert = data?['soundAlert'] ?? true;
              _vibrationAlert = data?['vibrationAlert'] ?? true;
              _smsAlert = data?['smsAlert'] ?? false;
              _drowsinessThreshold = data?['drowsinessThreshold'] ?? 3;
            });
          }
        }
      } catch (e) {
        print('Error loading user settings: $e');
      }
    }
  }

  Future<void> _initializeCamera() async {
    try {
      setState(() => _currentStatus = 'Requesting camera permission...');

      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          setState(() => _currentStatus = 'Camera permission denied');
        }
        return;
      }

      setState(() => _currentStatus = 'Initializing camera...');

      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) {
          setState(() => _currentStatus = 'No camera found');
        }
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
          _currentStatus = _isModelLoaded ? 'Ready to start' : 'Loading AI model...';
        });
        print("✅ Camera initialized successfully");
      }
    } catch (e) {
      print('Error initializing camera: $e');
      if (mounted) {
        setState(() => _currentStatus = 'Camera initialization failed: ${e.toString()}');
      }
    }
  }

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
      setState(() => _bluetoothStatus = 'Scanning...');
      devicesList.clear();
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      var subscription = FlutterBluePlus.scanResults.listen((results) {
        setState(() => devicesList = results.map((r) => r.device).toList());
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
      setState(() => _bluetoothStatus = 'Connection failed');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error connecting: $e')),
      );
    }
  }

  void _toggleMonitoring() {
    if (_isMonitoring) {
      _stopMonitoring();
    } else {
      _startMonitoring();
    }
  }

  void _startMonitoring() {
    if (!_isCameraInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera not initialized. Please check permissions.')),
      );
      // Try to reinitialize camera
      _initializeCamera();
      return;
    }

    setState(() {
      _isMonitoring = true;
      _currentStatus = 'Monitoring active...';
      _detectionCount = 0;
      _drowsinessStatus = 'Normal';
    });

    print('🚀 Monitoring started - Camera ready');
    if (!_isModelLoaded) {
      print('⚠️ Running without AI model (demo mode)');
    }

    _captureTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _captureAndRunInference();
    });
  }

  void _stopMonitoring() {
    setState(() {
      _isMonitoring = false;
      _currentStatus = 'Monitoring stopped';
      _drowsinessStatus = 'Normal';
    });
    _captureTimer?.cancel();
  }

  Future<void> _triggerAlerts() async {
    if (_soundAlert) _playAlertSound();
    if (_vibrationAlert) _triggerVibration();
    if (_smsAlert && _detectionCount >= _drowsinessThreshold) {
      final user = _auth.currentUser;
      if (user == null) return;
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final data = doc.data();
      _sendEmergencySMS(data);
    }
  }

  void _playAlertSound() async {
    try {
      await _audioPlayer.play(AssetSource('alert_sound.mp3'));
    } catch (e) {
      print('Error playing sound: $e');
    }
  }

  void _triggerVibration() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 1000, amplitude: 255);
    }
  }

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
    // Button is enabled as long as camera is ready
    bool isButtonEnabled = _isCameraInitialized;

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
            // Camera preview
            if (_isCameraInitialized && _isMonitoring)
              Container(
                height: 250,
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
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: isButtonEnabled ? _toggleMonitoring : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isMonitoring
                              ? Colors.red.shade400
                              : const Color(0xFF78C841),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          disabledForegroundColor: Colors.grey.shade500,
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
                    // Show status message if button is disabled
                    if (!isButtonEnabled) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.shade200,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.orange.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Waiting for camera initialization...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 12),
          Text(value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              )),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}