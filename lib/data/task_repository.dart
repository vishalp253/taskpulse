import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:uuid/uuid.dart';

class TaskItem {
  const TaskItem({required this.id, required this.title, required this.nextFireAt, required this.status, this.body = '', this.actionUrl = ''});
  final String id;
  final String title;
  final DateTime nextFireAt;
  final String status;
  final String body;
  final String actionUrl;

  factory TaskItem.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final fireAt = data['nextFireAt'];
    return TaskItem(id: doc.id, title: data['title'] as String? ?? 'Untitled task',
      nextFireAt: fireAt is Timestamp ? fireAt.toDate() : DateTime.now(),
      status: data['status'] as String? ?? 'scheduled', body: data['body'] as String? ?? '',
      actionUrl: data['actionUrl'] as String? ?? '');
  }
}

class TaskRepository {
  TaskRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance, _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  static const _uuid = Uuid();
  String get _uid => _auth.currentUser!.uid;
  CollectionReference<Map<String, dynamic>> get _tasks => _db.collection('tasks');

  Stream<List<TaskItem>> watchTasks() => _tasks.where('ownerId', isEqualTo: _uid)
      .orderBy('nextFireAt').snapshots().map((snapshot) => snapshot.docs.map(TaskItem.fromDocument).toList());

  Future<void> addTask({required String title, required DateTime when, String body = '', String actionUrl = ''}) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) throw ArgumentError('Enter a task title.');
    final id = _uuid.v4();
    await _tasks.doc(id).set({'ownerId': _uid, 'title': cleanTitle, 'body': body.trim(),
      'actionUrl': actionUrl.trim(), 'status': 'scheduled', 'nextFireAt': Timestamp.fromDate(when.toUtc()),
      'timezone': DateTime.now().timeZoneName, 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> complete(String id) => _setStatus(id, 'completed');
  Future<void> skip(String id) => _setStatus(id, 'skipped');
  Future<void> snooze(String id, Duration duration) async {
    await _ownedTask(id).update({'status': 'scheduled', 'nextFireAt': Timestamp.fromDate(DateTime.now().add(duration).toUtc()), 'updatedAt': FieldValue.serverTimestamp()});
  }
  Future<void> _setStatus(String id, String status) => _ownedTask(id).update({'status': status, 'updatedAt': FieldValue.serverTimestamp()});
  DocumentReference<Map<String, dynamic>> _ownedTask(String id) => _tasks.doc(id);

  Future<void> saveDeviceToken() async {
    if (!Platform.isAndroid || _auth.currentUser == null) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    final deviceId = '${Platform.operatingSystem}_${token.hashCode.abs()}';
    await _db.collection('users').doc(_uid).collection('user_devices').doc(deviceId).set({
      'fcmToken': token, 'platform': Platform.operatingSystem, 'enabled': true,
      'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) => _db.collection('users').doc(_uid)
      .collection('user_devices').doc(deviceId).set({'fcmToken': newToken, 'platform': Platform.operatingSystem,
        'enabled': true, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true)));
  }
}
