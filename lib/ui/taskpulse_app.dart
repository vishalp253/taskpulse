import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../data/task_repository.dart';
import '../desktop/desktop_services.dart';

class TaskPulseApp extends StatelessWidget {
  const TaskPulseApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(title: 'TaskPulse', navigatorKey: taskPulseNavigatorKey,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3659e3)), useMaterial3: true),
    routes: {'/quick-add': (_) => const _TaskEditorPage()}, home: const _AuthGate());
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(stream: FirebaseAuth.instance.authStateChanges(), builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (snapshot.data == null) return const _SignInPage();
    return const _TaskListPage();
  });
}

class _SignInPage extends StatefulWidget {
  const _SignInPage();
  @override
  State<_SignInPage> createState() => _SignInPageState();
}
class _SignInPageState extends State<_SignInPage> {
  final _email = TextEditingController(), _password = TextEditingController();
  bool _register = false, _busy = false;
  String? _error;
  @override
  void dispose() { _email.dispose(); _password.dispose(); super.dispose(); }
  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      final auth = FirebaseAuth.instance;
      if (_register) {
        await auth.createUserWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
      } else {
        await auth.signInWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
      }
    } on FirebaseAuthException catch (e) { setState(() => _error = e.message ?? e.code); }
    catch (e) { setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: Card(margin: const EdgeInsets.all(24), child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.notifications_active, size: 48), const SizedBox(height: 12), Text(_register ? 'Create your account' : 'Sign in to TaskPulse', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 20), TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
    const SizedBox(height: 12), TextField(controller: _password, obscureText: true, onSubmitted: (_) => _busy ? null : _submit(), decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
    if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    const SizedBox(height: 16), SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Please wait…' : (_register ? 'Create account' : 'Sign in')))),
    TextButton(onPressed: _busy ? null : () => setState(() { _register = !_register; _error = null; }), child: Text(_register ? 'Already registered? Sign in' : 'New here? Create an account')),
  ]))))));
}

class _TaskListPage extends StatefulWidget {
  const _TaskListPage();
  @override
  State<_TaskListPage> createState() => _TaskListPageState();
}
class _TaskListPageState extends State<_TaskListPage> {
  final _repo = TaskRepository();
  late final Stream<List<TaskItem>> _taskStream = _repo.watchTasks().asBroadcastStream();
  StreamSubscription<List<TaskItem>>? _desktopTaskSubscription;
  Timer? _desktopReminderTimer;
  List<TaskItem> _latestTasks = const [];
  final Set<String> _shownOccurrences = {};
  bool _showingReminder = false;

  @override
  void initState() {
    super.initState();
    _repo.saveDeviceToken().catchError((_) {});
    if (Platform.isWindows) {
      _desktopTaskSubscription = _taskStream.listen((tasks) {
        _latestTasks = tasks;
        _showDueReminderIfNeeded();
      });
      _desktopReminderTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _showDueReminderIfNeeded(),
      );
    }
  }

  @override
  void dispose() {
    _desktopReminderTimer?.cancel();
    _desktopTaskSubscription?.cancel();
    super.dispose();
  }

  void _showDueReminderIfNeeded() {
    if (!Platform.isWindows || _showingReminder) return;
    TaskItem? dueTask;
    String? occurrenceKey;
    final now = DateTime.now();
    for (final task in _latestTasks) {
      if (task.status != 'scheduled' || task.nextFireAt.isAfter(now)) continue;
      final key = '${task.id}_${task.nextFireAt.millisecondsSinceEpoch}';
      if (_shownOccurrences.contains(key)) continue;
      dueTask = task;
      occurrenceKey = key;
      break;
    }
    if (dueTask == null || occurrenceKey == null) return;

    final task = dueTask;
    final key = occurrenceKey;
    final context = taskPulseNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    _shownOccurrences.add(key);
    _showingReminder = true;
    // Do not wait for a render frame: Windows may stop painting a minimized
    // Flutter window, but the timer and notification channel remain active.
    unawaited(_deliverReminder(task, context));
  }

  Future<void> _deliverReminder(
    TaskItem task,
    BuildContext context,
  ) async {
    try {
      await DesktopServices.instance.showAlert(
        context,
        taskId: task.id,
        title: task.title,
        actionUrl: task.actionUrl,
      );
    } catch (error) {
      debugPrint('Could not deliver TaskPulse reminder: $error');
    } finally {
      _showingReminder = false;
      if (mounted) _showDueReminderIfNeeded();
    }
  }

  Future<void> _edit() async { await Navigator.of(context).pushNamed('/quick-add'); }
  Future<void> _action(Future<void> Function() action) async {
    try { await action(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update task: $e'))); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('TaskPulse'), actions: [IconButton(tooltip: 'Sign out', onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout))]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _edit, icon: const Icon(Icons.add), label: const Text('Add task')),
    body: StreamBuilder<List<TaskItem>>(stream: _taskStream, builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Unable to load tasks. Check your Firebase setup and Firestore index.\n${snapshot.error}', textAlign: TextAlign.center)));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final tasks = snapshot.data!;
      if (tasks.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.check_circle_outline, size: 56), const SizedBox(height: 12), const Text('No tasks yet'), const SizedBox(height: 8), FilledButton.icon(onPressed: _edit, icon: const Icon(Icons.add), label: const Text('Create your first task'))]));
      return ListView.builder(padding: const EdgeInsets.only(bottom: 90), itemCount: tasks.length, itemBuilder: (context, i) {
        final task = tasks[i], done = task.status == 'completed' || task.status == 'skipped';
        return Card(margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: ListTile(leading: Icon(done ? Icons.check_circle : Icons.alarm, color: done ? Colors.green : null),
          title: Text(task.title, style: TextStyle(decoration: done ? TextDecoration.lineThrough : null)), subtitle: Text('${task.nextFireAt.toLocal()}  •  ${task.status}${task.body.isEmpty ? '' : '\n${task.body}'}'), isThreeLine: task.body.isNotEmpty,
          trailing: PopupMenuButton<String>(onSelected: (value) => _action(() async {
            if (value == 'done') await _repo.complete(task.id);
            if (value == 'snooze') await _repo.snooze(task.id, const Duration(minutes: 10));
            if (value == 'skip') await _repo.skip(task.id);
            if (value == 'delete') await FirebaseFirestore.instance.collection('tasks').doc(task.id).delete();
          }), itemBuilder: (_) => [if (!done) const PopupMenuItem(value: 'done', child: Text('Mark done')), if (!done) const PopupMenuItem(value: 'snooze', child: Text('Snooze 10 minutes')), if (!done) const PopupMenuItem(value: 'skip', child: Text('Skip')), const PopupMenuItem(value: 'delete', child: Text('Delete'))])));
      });
    }));
}

class _TaskEditorPage extends StatefulWidget {
  const _TaskEditorPage();
  @override
  State<_TaskEditorPage> createState() => _TaskEditorPageState();
}
class _TaskEditorPageState extends State<_TaskEditorPage> {
  final _title = TextEditingController(), _body = TextEditingController(), _actionUrl = TextEditingController();
  DateTime _when = DateTime.now().add(const Duration(minutes: 10));
  bool _saving = false;
  String? _error;
  @override
  void dispose() { _title.dispose(); _body.dispose(); _actionUrl.dispose(); super.dispose(); }
  Future<void> _pickDateTime() async {
    final date = await showDatePicker(context: context, initialDate: _when, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 3650)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (time != null) setState(() => _when = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }
  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try { await TaskRepository().addTask(title: _title.text, when: _when, body: _body.text, actionUrl: _actionUrl.text); if (mounted) Navigator.pop(context); }
    catch (e) { setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _saving = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Add task')), body: ListView(padding: const EdgeInsets.all(20), children: [
    TextField(controller: _title, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Task title', hintText: 'Practice Spanish', border: OutlineInputBorder())),
    const SizedBox(height: 14), TextField(controller: _body, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder())),
    const SizedBox(height: 14), TextField(controller: _actionUrl, decoration: const InputDecoration(labelText: 'Action link (optional)', hintText: 'https://… or a file path', border: OutlineInputBorder())),
    const SizedBox(height: 14), OutlinedButton.icon(onPressed: _pickDateTime, icon: const Icon(Icons.schedule), label: Text('Due ${MaterialLocalizations.of(context).formatMediumDate(_when)} at ${TimeOfDay.fromDateTime(_when).format(context)}')),
    if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    const SizedBox(height: 18), FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save task')),
  ]));
}
