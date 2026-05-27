import 'package:flutter/material.dart';

import 'skeleton.dart';

abstract class DataPage<T extends StatefulWidget> extends State<T>
    with WidgetsBindingObserver {
  static const Duration _resumeRefreshCooldown = Duration(seconds: 2);

  bool _loading = true;
  bool _loadedOnce = false;
  Object? _error;
  DateTime? _lastResumeRefreshAt;
  Future<void>? _inFlightLoad;

  Future<void> onLoad();

  Future<void> onRefresh() => onLoad();

  Widget buildPage(BuildContext context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _runLoad());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runRefreshOnResume();
    }
  }

  Future<void> _runRefreshOnResume() async {
    if (!_loadedOnce || _loading) {
      return;
    }

    final DateTime now = DateTime.now();
    final DateTime? lastRefreshAt = _lastResumeRefreshAt;
    if (lastRefreshAt != null && now.difference(lastRefreshAt) < _resumeRefreshCooldown) {
      return;
    }

    _lastResumeRefreshAt = now;

    await _runLoad(isRefresh: true);
  }

  Future<void> _runLoad({bool isRefresh = false}) async {
    final Future<void>? existingLoad = _inFlightLoad;
    if (existingLoad != null) {
      return existingLoad;
    }

    final Future<void> load = _runLoadInternal(isRefresh: isRefresh);
    _inFlightLoad = load;
    try {
      await load;
    } finally {
      if (identical(_inFlightLoad, load)) {
        _inFlightLoad = null;
      }
    }
  }

  Future<void> _runLoadInternal({required bool isRefresh}) async {
    setState(() {
      _loading = true;
      if (!isRefresh) {
        _error = null;
      }
    });

    try {
      if (isRefresh) {
        await onRefresh();
      } else {
        await onLoad();
      }
    } catch (error) {
      _error = error;
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadedOnce = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: MedRashSkeletonList(rowCount: 4),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Something went wrong: $_error'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _runLoad,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return buildPage(context);
  }
}