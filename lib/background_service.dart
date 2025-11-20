
import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';

void initializeService() {
  final service = FlutterBackgroundService();

  service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'my_foreground',
      initialNotificationTitle: 'Driver Safety Service',
      initialNotificationContent: 'Monitoring in progress',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );

  service.startService();



  FlutterBackgroundService().startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) {
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: "Driver Safety Monitor Service",
      content: "Monitoring driver in background",
    );
  }

  Timer.periodic(const Duration(seconds: 10), (timer) async {
    // Execute your ML monitoring logic here...

    // Example: Send log to UI
    service.invoke('update', {
      "current_date": DateTime.now().toIso8601String(),
    });

    // Stop service if requested (optional)
    final event = await service.on('stopService').first;
    if (event != null) {
      timer.cancel();
      service.stopSelf();
    }
  });
}

bool onIosBackground(ServiceInstance service) {
  // Handle iOS background
  return true;
}
