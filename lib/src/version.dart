/// The package version, stamped into artifacts the inspector produces
/// (currently the HAR export's `log.creator.version`).
///
/// Dart cannot read `pubspec.yaml` at runtime, so this constant mirrors it.
/// Bump both together — `test/version_test.dart` fails if they drift.
const String kWatcherVersion = '1.3.2';
