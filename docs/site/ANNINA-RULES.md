# Annina Rules

Use these rules when rewriting or creating Proximi.io Flutter map documentation. They are
the rules of the iOS and Android SDK sites, with the platform facts adapted to Flutter.

## Objective

Write concise technical documentation for developers. State API behaviour
directly and preserve its exact meaning.

Do not turn documentation into literature. Do not add marketing language,
narrative, metaphors, rhetorical questions, or dramatic transitions.

## Audience and publication scope

Classify the documentation as public or internal before deciding which details
to include. If the intended audience is unclear, establish it with the product
owner before publishing.

Public integration documentation includes supported setup steps, required
configuration, public API behaviour and information needed to operate or debug
an integration.

Keep implementation internals, unpublished modules, vendor wire protocols,
internal tuning constants, design rationale, test infrastructure and
source-code discrepancies in internal documentation unless a public developer
must act on them.

For positioning features, explain inputs, permissions, configuration, output
and observable limitations. Keep algorithm stages, filter internals,
arbitration rules and tuning rationale internal unless they are part of the
supported public integration.

## Writing rules

1. Start with what the API does and when to use it.
2. State prerequisites, required inputs, defaults, and units.
3. State lifecycle, failure, permission, and background behaviour when relevant.
4. Use short paragraphs and one main fact per sentence.
5. Prefer exact public symbols and values over abstract descriptions.
6. Remove text that does not help implementation, configuration, debugging, or
   evaluation.
7. Do not repeat facts already clear from a code sample or table.
8. Do not change API signatures or behaviour to improve the prose.

Use neutral technical English. Avoid marketing claims, anthropomorphism,
conversational filler, literary phrases, and unexplained claims such as “safe”,
“fast”, or “reliable”. Use “setting” or “property”, never “knob”.

Use declarative technical headings and sentences. Avoid rhetorical questions,
second-person scene setting, jokes, metaphors and narrative transitions. Imperative
instructions are acceptable when they state a concrete integration step.

## Technical verification

Verify implementation-specific statements against the current source:

- public names and signatures;
- default values and units;
- iOS and Android version, Info.plist, manifest and runtime-permission requirements;
- stream start, stop, restart and error behaviour;
- Android foreground-service and iOS background behaviour;
- where the two platforms differ (state it per platform, never average it);
- coordinate order and floor handling;
- distinctions between similarly named systems.

If source and existing documentation disagree, document the source behaviour and
report the discrepancy. Do not guess.

## Terminology

- Write **BlueIoT** in prose. Preserve code symbols exactly as
  the Dart API spells them.
- Write **Proximi.io Portal** for the venue configuration product.
- Never use “storey”; use “floor”.
- Distinguish venue-side RTLS from positioning performed by the phone.
- Distinguish **BlueIoT AoA**, **BlueIoT UWB**, and **phone-native UWB**.

BlueIoT AoA and BlueIoT UWB are venue-side systems. The venue infrastructure
computes the position, and the phone receives the result through a relay
or direct engine connection. Phone-native UWB uses the phone.s UWB radio
to range against compatible anchors.

The BLE phone-as-tag feature applies to BlueIoT AoA. It does not turn the phone
into a BlueIoT UWB tag.

## Geofencing

The normal geofencing path is the Proximi.io SDK:

1. Define circular or polygonal geofences in Proximi.io Portal.
2. The SDK evaluates every published position, including BLE, phone-native UWB,
   relay-fed, and direct-provider positions.
3. Collect events from `proximiio.geofenceEvents()`.
4. Evaluation uses the resolved floor of the position.

Venue-engine area events are internal unless a public integration explicitly
requires them. Do not mix them into the normal geofencing guide.

## Page structure

Task guide, as applicable:

1. Definition and use case
2. Minimal working example
3. Required configuration
4. Behaviour and lifecycle
5. Errors and limitations
6. Related reference links

API reference, as applicable:

1. Exact declaration
2. Parameters or properties
3. Return value
4. Errors
5. Lifecycle and concurrency
6. Minimal example

Do not add an introduction or conclusion that only repeats the page.

## Samples, tables, and notes

- Use the smallest complete sample with real public symbols and valid call order.
- Explain only non-obvious constraints in code comments.
- Use tables for repeated fields, defaults, and effects.
- Use notes only when omission could cause an incorrect implementation.
- Reserve warnings for data loss, privacy, security, permissions, or irreversible
  behaviour.

## Final review

- Every paragraph contains implementation-relevant information.
- Defaults, units, permissions, floors, and lifecycle are explicit.
- BlueIoT AoA, BlueIoT UWB, and phone-native UWB are clearly separated.
- The main geofence guide uses `sdk.geofenceEvents`.
- Advanced venue-engine events are separate from normal geofencing.
- Internal algorithms, protocols, tuning constants and test details are not
  present in public integration documentation.
- Code samples match the current Dart API (`lib/`) and compile against it.
- Every symbol exists in the Dart API; the native names are mentioned only where a
  reader needs to map them (migration, platform differences).
- Strict build and link checks pass.
