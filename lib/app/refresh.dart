import 'package:flutter/foundation.dart';

/// Bumped after every successful write and when the app returns to the
/// foreground, so all open lists re-sync with ERPNext (FR-055).
final ValueNotifier<int> refreshTick = ValueNotifier<int>(0);

void bumpRefresh() => refreshTick.value++;
