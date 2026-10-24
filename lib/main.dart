import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskpulse/desktop/desktop_services.dart';
import 'package:taskpulse/ui/taskpulse_app.dart';
import 'package:window_manager/window_manager.dart';

import 'firebase_options.dart';

final localNotifications = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (Platform.isAndroid) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await _initializeNotifications();
  }
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.setTitle('TaskPulse');
    await DesktopServices.instance.initialize();
  }
  runApp(const ProviderScope(child: TaskPulseApp()));
  await _initializeMessaging();
}

Future<void> _initializeNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const settings = InitializationSettings(android: android, iOS: DarwinInitializationSettings());
  await localNotifications.initialize(settings, onDidReceiveNotificationResponse: (response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) openTaskAction(payload);
  });
  await localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(
    const AndroidNotificationChannel('taskpulse_reminders', 'Task reminders', description: 'Scheduled TaskPulse alerts', importance: Importance.max));
}

Future<void> _initializeMessaging() async {
  if (!Platform.isAndroid) return;
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);
  await messaging.getToken(); // Persist this token with DeviceRepository after sign-in.
  FirebaseMessaging.onMessage.listen((message) async {
    final title = message.notification?.title ?? 'TaskPulse reminder';
    final body = message.notification?.body ?? 'A task is due now.';
    await localNotifications.show(message.hashCode, title, body,
      const NotificationDetails(android: AndroidNotificationDetails('taskpulse_reminders', 'Task reminders', importance: Importance.max, priority: Priority.high)),
      payload: message.data['actionUrl'] as String? ?? '');
  });
}

Future<void> openTaskAction(String value) async {
  // Desktop overlay and deep-link handling are implemented in desktop_services.dart.
  await DesktopServices.instance.openAction(value);
}
