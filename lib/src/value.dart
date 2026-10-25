import 'package:flutter/foundation.dart';

/// Value equality from a list of fields, for the public models. Not exported.
mixin ValueEquality {
  /// The fields that make up the value, in a fixed order.
  List<Object?> get props;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType && other is ValueEquality && _deepEquals(props, other.props);

  @override
  int get hashCode => Object.hashAll(props.map(_deepHash));
}

bool _deepEquals(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is Set && b is Set) return setEquals(a, b);
  return a == b;
}

int _deepHash(Object? value) => switch (value) {
  final List<Object?> list => Object.hashAll(list.map(_deepHash)),
  final Map<Object?, Object?> map => Object.hashAllUnordered(
    map.entries.map((e) => Object.hash(_deepHash(e.key), _deepHash(e.value))),
  ),
  final Set<Object?> set => Object.hashAllUnordered(set.map(_deepHash)),
  _ => value.hashCode,
};
