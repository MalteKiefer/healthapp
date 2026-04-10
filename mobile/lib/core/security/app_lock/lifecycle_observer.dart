import 'package:flutter/widgets.dart';
import 'package:healthapp/core/security/app_lock/app_lock_controller.dart';

/// Bridges Flutter's app lifecycle events to the AppLockController.
class SecurityLifecycleObserver extends WidgetsBindingObserver {
  SecurityLifecycleObserver(this.controller);

  final AppLockController controller;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        controller.onBackgrounded();
        break;
      case AppLifecycleState.resumed:
        controller.onResumed();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }
}
