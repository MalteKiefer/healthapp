import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shared M3 page transitions. Used via go_router's `pageBuilder`.
///
/// Every transition respects `MediaQuery.of(context).disableAnimations`
/// for reduced-motion accessibility: when enabled, returns the child
/// immediately with no animation.
class AppTransitions {
  AppTransitions._();

  /// Slide from right (forward) + fade. M3 "shared axis X" feel.
  static CustomTransitionPage<T> slideX<T>({
    required Widget child,
    Duration duration = const Duration(milliseconds: 250),
  }) {
    return CustomTransitionPage<T>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      child: child,
      transitionsBuilder: (context, animation, secondary, widget) {
        if (MediaQuery.of(context).disableAnimations) return widget;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: widget),
        );
      },
    );
  }

  /// Fade-only transition for modal-like screens (lock screen, setup PIN).
  static CustomTransitionPage<T> fade<T>({
    required Widget child,
    Duration duration = const Duration(milliseconds: 180),
  }) {
    return CustomTransitionPage<T>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      child: child,
      transitionsBuilder: (context, animation, secondary, widget) {
        if (MediaQuery.of(context).disableAnimations) return widget;
        return FadeTransition(opacity: animation, child: widget);
      },
    );
  }
}
