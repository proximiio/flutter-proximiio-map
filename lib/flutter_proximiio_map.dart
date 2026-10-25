/// The Proximi.io venue map for Flutter: a platform view over the native Proximi.io Map v6.
///
/// Create the SDK with `Proximiio.create` (package flutter_proximiio), then show a [ProximiioMap].
library;

import 'src/widget.dart';

export 'src/controller.dart'
    show
        JourneyNavigator,
        MapCameraState,
        MapFeatureTap,
        MapFloor,
        MapFloorSelection,
        MapStyleSource,
        ProximiioMapController;
export 'src/errors.dart' show MapErrorCode, ProximiioMapException;
export 'src/guidance.dart';
export 'src/journey_models.dart';
export 'src/options.dart';
export 'src/widget.dart';
