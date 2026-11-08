import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tokens.dart';
import 'v13_button.dart';
import 'v13_skeleton.dart';

enum V13AsyncStatus { loading, error, empty, data }

/// The one state widget for every network surface in v13:
/// skeleton while loading, a friendly error with Retry, an empty state, and
/// the data builder. Pull-to-refresh via [onRefresh].
///
/// Feed it an `AsyncValue<T>` (the default constructor) or drive it
/// manually with [V13AsyncView.state].
class V13AsyncView<T> extends StatelessWidget {
  const V13AsyncView({
    super.key,
    required AsyncValue<T> this.value,
    required this.builder,
    this.isEmpty,
    this.emptyTitle = 'Nothing here yet',
    this.emptyBody,
    this.emptyIcon = Icons.flag_outlined,
    this.emptyAction,
    this.onRetry,
    this.onRefresh,
    this.loadingWidget,
    this.errorTitle = 'Something went wrong',
    this.errorBody = 'Check your connection and try again.',
  }) : status = null,
       dataValue = null,
       errorValue = null;

  /// Explicit-state drive — for screens that assemble their own status.
  const V13AsyncView.state({
    super.key,
    required V13AsyncStatus this.status,
    this.dataValue,
    this.errorValue,
    required this.builder,
    this.isEmpty,
    this.emptyTitle = 'Nothing here yet',
    this.emptyBody,
    this.emptyIcon = Icons.flag_outlined,
    this.emptyAction,
    this.onRetry,
    this.onRefresh,
    this.loadingWidget,
    this.errorTitle = 'Something went wrong',
    this.errorBody = 'Check your connection and try again.',
  }) : value = null;

  /// Riverpod source — preferred drive.
  final AsyncValue<T>? value;

  /// Explicit state when [value] is null (the `.state` constructor).
  final V13AsyncStatus? status;
  final T? dataValue;
  final Object? errorValue;

  /// Builds the data state.
  final Widget Function(T data) builder;

  /// Empty detection on resolved data — e.g. `(list) => list.isEmpty`.
  /// When it returns true the empty state renders instead of [builder].
  final bool Function(T data)? isEmpty;

  final String emptyTitle;
  final String? emptyBody;
  final IconData emptyIcon;

  /// Optional CTA rendered under the empty copy.
  final Widget? emptyAction;

  /// Retry callback — the error state's button. Hidden when null (no dead
  /// buttons), so pass it whenever a retry is possible.
  final VoidCallback? onRetry;

  /// Pull-to-refresh. Wraps the resolved view in a [RefreshIndicator].
  final Future<void> Function()? onRefresh;

  /// Custom loading view — defaults to [V13Skeleton.screen].
  final Widget? loadingWidget;

  final String errorTitle;
  final String errorBody;

  V13AsyncStatus _resolve() {
    final s = status;
    if (s != null) return s;
    final v = value;
    if (v == null) return V13AsyncStatus.loading;
    if (v.hasValue) {
      final d = v.value as T;
      if (isEmpty != null && isEmpty!(d)) return V13AsyncStatus.empty;
      return V13AsyncStatus.data;
    }
    if (v.hasError) return V13AsyncStatus.error;
    return V13AsyncStatus.loading;
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolve();
    Widget content = switch (resolved) {
      V13AsyncStatus.loading => loadingWidget ?? const V13Skeleton.screen(),
      V13AsyncStatus.error => _ErrorView(
        title: errorTitle,
        body: errorBody,
        onRetry: onRetry,
      ),
      V13AsyncStatus.empty => _EmptyView(
        icon: emptyIcon,
        title: emptyTitle,
        body: emptyBody,
        action: emptyAction,
      ),
      V13AsyncStatus.data => builder(_data()),
    };

    final refresh = onRefresh;
    if (refresh != null) {
      if (resolved == V13AsyncStatus.data) {
        // The data builder owns scrolling; it must be scrollable for the
        // pull gesture to be reachable.
        content = RefreshIndicator(
          color: V13.blue,
          onRefresh: refresh,
          child: content,
        );
      } else {
        // Non-scrollable states still get the gesture.
        content = LayoutBuilder(
          builder: (context, constraints) => RefreshIndicator(
            color: V13.blue,
            onRefresh: refresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: content,
              ),
            ),
          ),
        );
      }
    }
    return content;
  }

  T _data() {
    if (status != null) return dataValue as T;
    return value!.value as T;
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.title, required this.body, this.onRetry});

  final String title;
  final String body;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(V13.gapXxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 44, color: V13.muted),
            const SizedBox(height: V13.gapLg),
            Text(title, style: V13.sectionHead, textAlign: TextAlign.center),
            const SizedBox(height: V13.gapSm),
            Text(body, style: V13.caption, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: V13.gapXl),
              V13Button.secondary(label: 'Retry', onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(V13.gapXxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: V13.muted),
            const SizedBox(height: V13.gapLg),
            Text(title, style: V13.sectionHead, textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: V13.gapSm),
              Text(body!, style: V13.caption, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: V13.gapXl), action!],
          ],
        ),
      ),
    );
  }
}
