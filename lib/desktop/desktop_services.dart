import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/task_repository.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:system_tray/system_tray.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:win_toast/win_toast.dart';

import 'sticky_overlay_widget.dart';

class DesktopServices {
  DesktopServices._();
  static final instance = DesktopServices._();
  final _tray = SystemTray();
  final _hotkey = HotKeyManager.instance;
  bool _toastReady = false;

  Future<void> initialize() async {
    if (!Platform.isWindows) return;
    _toastReady = await WinToast.instance().initialize(
      aumId: 'com.taskpulse.desktop',
      displayName: 'TaskPulse',
      iconPath: '',
      clsid: '6F9C6DA1-82B6-4B2D-9AF3-533A0A6A3D20',
    );
    await _hotkey.unregisterAll();
    await _hotkey.register(
      HotKey(
        key: LogicalKeyboardKey.keyT,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      ),
      keyDownHandler: (_) => showQuickAdd(),
    );

    // Fixed: added required iconPath parameter
    await _tray.initSystemTray(
      title: 'TaskPulse',
      iconPath: 'assets/icons/app_icon.ico',
      toolTip: 'TaskPulse reminders',
    );

    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: 'Open TaskPulse',
        onClicked: (_) => windowManager.show(),
      ),
      MenuItemLabel(
        label: 'Quick add task',
        onClicked: (_) => showQuickAdd(),
      ),
      MenuItemLabel(
        label: 'Quit',
        onClicked: (_) async {
          await _hotkey.unregisterAll();
          exit(0);
        },
      ),
    ]);
    await _tray.setContextMenu(menu);

    // Fixed: register event handler callback properly
    _tray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        windowManager.show();
      }
    });
  }

  Future<void> showQuickAdd() async {
    await windowManager.show();
    taskPulseNavigatorKey.currentState?.pushNamed('/quick-add');
  }

  Future<void> showAlert(
    BuildContext context, {
    required String taskId,
    required String title,
    String? actionUrl,
  }) async {
    await SystemSound.play(SystemSoundType.alert);
    final minimized = await windowManager.isMinimized();
    final focused = await windowManager.isFocused();
    // Deliver a Windows toast whenever the user is working in another app,
    // including when TaskPulse is merely behind the browser rather than minimized.
    if (minimized || !focused) {
      final safeTitle = _escapeXml(title);
      if (_toastReady) {
        try {
          await WinToast.instance().showCustomToast(
            xml: '''<?xml version="1.0" encoding="UTF-8"?>
<toast><visual><binding template="ToastGeneric">
<text>$safeTitle</text><text>Task is due now.</text>
</binding></visual><audio src="ms-winsoundevent:Notification.Default"/></toast>''',
          );
          return;
        } catch (error) {
          debugPrint('Could not show TaskPulse Windows toast: $error');
        }
      }
    }
    await windowManager.show();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StickyOverlayWidget(
        taskId: taskId,
        title: title,
        actionUrl: actionUrl,
      ),
    );
  }

  String _escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  Future<void> openAction(String value) async {
    if (value.trim().isEmpty) return;
    final uri = Uri.tryParse(value);
    if (uri == null) return;
    if (uri.scheme == 'http' ||
        uri.scheme == 'https' ||
        uri.scheme.endsWith('+vscode') ||
        uri.scheme == 'vscode') {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (Platform.isWindows && !uri.hasScheme) {
      await launchUrl(Uri.file(value), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> markDone(String taskId) => TaskRepository().complete(taskId);
  Future<void> snooze(String taskId, Duration duration) =>
      TaskRepository().snooze(taskId, duration);
  Future<void> skip(String taskId) => TaskRepository().skip(taskId);
}

final GlobalKey<NavigatorState> taskPulseNavigatorKey =
    GlobalKey<NavigatorState>();
