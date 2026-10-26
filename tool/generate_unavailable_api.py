#!/usr/bin/env python3
"""Regenerates ios/.../UnavailableMapApi.swift from the generated MapHostApi protocol.

Run after `dart run pigeon --input pigeons/messages.dart`:
    python3 tool/generate_unavailable_api.py
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "ios/flutter_proximiio_map/Sources/flutter_proximiio_map"

body = re.search(r"protocol MapHostApi \{(.*?)\n\}", (SOURCES / "MapMessages.g.swift").read_text(), re.S).group(1)
lines = [
    "// Generated from MapMessages.g.swift by tool/generate_unavailable_api.py; do not edit.",
    "import Foundation",
    "",
    "/// Answers every map call with one error (no map library, or no SDK instance). `dispose()`",
    "/// succeeds and runs `onDispose`, so the notice can release its channels.",
    "final class UnavailableMapApi: MapHostApi {",
    "  private let error: MapFlutterError",
    "  private let onDispose: () -> Void",
    "",
    "  init(error: MapFlutterError, onDispose: @escaping () -> Void) {",
    "    self.error = error",
    "    self.onDispose = onDispose",
    "  }",
    "",
]
for line in (l.strip() for l in body.splitlines()):
    if not line.startswith("func "):
        continue
    if line.startswith("func dispose()"):
        lines.append("  " + line + " { onDispose() }")
        continue
    suffix = " { completion(.failure(error)) }" if "completion: @escaping" in line else " { throw error }"
    lines.append("  " + line + suffix)
lines.append("}")
(SOURCES / "UnavailableMapApi.swift").write_text("\n".join(lines) + "\n")

# Kotlin: android/.../UnavailableMapApi.kt from the generated MapHostApi interface.
KOTLIN = ROOT / "android/src/main/kotlin/io/proximi/flutter_proximiio_map"
kt = (KOTLIN / "MapMessages.g.kt").read_text()
interface = re.search(r"interface MapHostApi \{(.*?)\n  companion object", kt, re.S).group(1)
out = [
    "// Generated from MapMessages.g.kt by tool/generate_unavailable_api.py; do not edit.",
    "package io.proximi.flutter_proximiio_map",
    "",
    "/**",
    " * Answers every map call with one error (no SDK instance, or no options). `dispose()` succeeds and",
    " * runs [onDispose], so the notice can release its channels.",
    " */",
    "internal class UnavailableMapApi(private val error: MapFlutterError, private val onDispose: () -> Unit) : MapHostApi {",
]
for line in (l.strip() for l in interface.splitlines()):
    if not line.startswith("fun "):
        continue
    if line.startswith("fun dispose()"):
        out.append("  override " + line + " = onDispose()")
        continue
    if "callback: (Result<" in line:
        out.append("  override " + line + " = callback(Result.failure(error))")
    else:
        out.append("  override " + line + " = throw error")
out.append("}")
(KOTLIN / "UnavailableMapApi.kt").write_text("\n".join(out) + "\n")
