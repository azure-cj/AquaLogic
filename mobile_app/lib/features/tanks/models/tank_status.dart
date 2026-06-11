import 'package:aqualogic/shared/models/reading_state.dart';

ReadingState tankStatusState(String status) {
  return switch (status) {
    'NORMAL' => ReadingState.normal,
    'CRITICAL' => ReadingState.critical,
    _ => ReadingState.warning,
  };
}
