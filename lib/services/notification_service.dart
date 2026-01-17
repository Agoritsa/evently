import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  static Future<bool> requestPermission() async {
    final bool? granted = await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestPermission();

    return granted ?? false;
  }

  static Future<void> showLocalNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'profile_channel',
      'Profile Notifications',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);

    await _flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      notificationDetails,
    );
  }

  static Future<void> checkUpcomingFavoriteEvents() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final favoritesSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('favorites')
        .get();

    final now = DateTime.now();
    final in48Hours = now.add(Duration(hours: 48));

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final notificationsEnabled = userDoc.data()?['notificationsEnabled'] ?? true;
    if (!notificationsEnabled) return;

    final notifiedEventsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifiedEvents');

    const cooldownDuration = Duration(hours: 24);

    for (final doc in favoritesSnapshot.docs) {
      final data = doc.data();
      final eventId = data['id'];
      if (data['date'] == null || data['name'] == null || eventId == null) continue;

      final eventDate = DateTime.tryParse(data['date']);
      if (eventDate == null) continue;

      if (eventDate.isAfter(now) && eventDate.isBefore(in48Hours)) {
        final notifiedDoc = await notifiedEventsRef.doc(eventId).get();
        DateTime? lastNotified;
        if (notifiedDoc.exists) {
          final timestamp = notifiedDoc.data()?['notifiedAt'];
          if (timestamp is Timestamp) {
            lastNotified = timestamp.toDate();
          }
        }

        final shouldNotify = lastNotified == null || now.difference(lastNotified) > cooldownDuration;

        if (shouldNotify) {
          const androidDetails = AndroidNotificationDetails(
            'event_channel',
            'Upcoming Events',
            importance: Importance.max,
            priority: Priority.high,
          );

          const notificationDetails = NotificationDetails(android: androidDetails);

          await _flutterLocalNotificationsPlugin.show(
            eventId.hashCode,
            'Upcoming Event',
            '${data['name']} is happening soon!',
            notificationDetails,
          );

          // Update notification timestamp for this event
          await notifiedEventsRef.doc(eventId).set({
            'notifiedAt': Timestamp.fromDate(now),
          });
        }
      }
    }
  }
}
