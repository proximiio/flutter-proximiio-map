import 'package:flutter/services.dart';
import 'package:flutter_proximiio/flutter_proximiio.dart';

/// What went wrong with a map call.
enum MapErrorCode {
  /// No SDK instance: call `Proximiio.create` before showing the map.
  notConfigured,

  /// The map was disposed, or its view is gone.
  notReady,

  /// A journey call without a running journey.
  noJourney,

  /// The order proposal is unknown or was applied already.
  unknownProposal,

  /// A value was rejected (Android; iOS reports rejected values as [underlying]).
  invalidArgument,

  /// A later `showRoute`, `clearRoute` or `startJourney` replaced this route call; nothing was drawn.
  superseded,

  /// Not available on this platform or build (iOS without Swift Package Manager).
  unsupported,

  /// Another failure inside the map library.
  underlying,

  /// A code added after this plugin release.
  unknown,
}

/// An error from the map. Route failures are [ProximiioException]s with [ProximiioErrorCode.noRoute],
/// as from `Proximiio.computeRoute`.
class ProximiioMapException implements Exception {
  /// Creates an exception.
  const ProximiioMapException(this.code, {this.message});

  /// Converts a platform error from the bridge.
  factory ProximiioMapException.fromPlatform(PlatformException error) => ProximiioMapException(
    MapErrorCode.values.asNameMap()[error.code] ?? MapErrorCode.unknown,
    message: error.message,
  );

  /// What went wrong.
  final MapErrorCode code;

  /// A description for logs.
  final String? message;

  @override
  String toString() => 'ProximiioMapException(${code.name}${message == null ? '' : ': $message'})';
}

/// Runs a bridge call and turns platform errors into [ProximiioException] (routes) or
/// [ProximiioMapException] (everything else).
Future<T> guardedMap<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on PlatformException catch (error) {
    if (error.code == 'noRoute') throw ProximiioException.fromPlatform(error);
    throw ProximiioMapException.fromPlatform(error);
  }
}
