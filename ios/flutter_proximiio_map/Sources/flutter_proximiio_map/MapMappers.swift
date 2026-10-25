#if canImport(ProximiioMap)
import CoreLocation
import Foundation
import Proximiio
import ProximiioMap

/// Converts between the map library's types and the Pigeon transport types (`MapMsg*`).
enum MapMappers {

  // MARK: Options

  static func color(_ argb: Int64) -> MapColor {
    let value = UInt32(truncatingIfNeeded: argb)
    return MapColor(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255,
      alpha: Double((value >> 24) & 0xFF) / 255
    )
  }

  static func edgeInsets(_ value: MapMsgEdgeInsets) -> MapEdgeInsets {
    MapEdgeInsets(top: value.top, leading: value.leading, bottom: value.bottom, trailing: value.trailing)
  }

  static func toggles(_ value: MapMsgLayerToggles) -> MapLayerToggles {
    MapLayerToggles(
      paths: value.paths,
      walls: value.walls,
      shops: value.shops,
      pois: value.pois,
      amenities: value.amenities,
      baseTiles: value.baseTiles
    )
  }

  static func options(_ msg: MapMsgOptions) -> MapOptions {
    let camera: MapOptions.Camera
    switch msg.camera {
    case .free: camera = .free
    case .follow: camera = .follow
    case .followWithHeading: camera = .followWithHeading
    }
    let floorSelector: MapOptions.FloorSelector
    switch msg.floorSelector {
    case .none: floorSelector = .none
    case .leading: floorSelector = .leading
    case .trailing: floorSelector = .trailing
    }
    let trail: MapOptions.Trail
    switch msg.trail {
    case .off: trail = .off
    case .lastMinutes: trail = .lastMinutes(msg.trailValue ?? 1)
    case .lastFixes: trail = .lastFixes(Int(msg.trailValue ?? 30))
    }
    let features: MapOptions.Features
    switch msg.features {
    case .venueDefaults: features = .venueDefaults
    case .none: features = .none
    case .only: features = .only(msg.layerToggles.map(toggles) ?? .all)
    }
    let insets: MapOptions.ContentInsets
    switch msg.insets {
    case .none: insets = .none
    case .safeArea: insets = .safeArea
    case .fixed: insets = .fixed(msg.insetValues.map(edgeInsets) ?? .zero)
    case .safeAreaPlus: insets = .safeAreaPlus(msg.insetValues.map(edgeInsets) ?? .zero)
    }
    let defaults = MapOptions()
    var options = MapOptions(
      camera: camera,
      floorSelector: floorSelector,
      trail: trail,
      features: features,
      route: msg.showsRoute ? .automatic : .off,
      routeMarkers: msg.routeMarkers.map {
        RouteMarkerStyle(isVisible: $0.isVisible, color: color($0.color), completedColor: color($0.completedColor))
      } ?? .venue,
      geofences: msg.showsGeofences ? .automatic : .off,
      geofenceStyle: msg.geofenceStyle.map {
        GeofenceStyle(
          fillColor: color($0.fillColor),
          fillOpacity: $0.fillOpacity,
          lineColor: color($0.lineColor),
          lineWidthPoints: $0.lineWidth
        )
      } ?? .venue,
      contentInsets: insets,
      amenities: msg.amenities,
      position: .venue,
      fallbackStyleURL: msg.fallbackStyleUrl.flatMap(URL.init(string:)) ?? defaults.fallbackStyleURL,
      recentreZoom: msg.recentreZoom ?? defaults.recentreZoom,
      offlinePackageId: msg.offlinePackageId
    )
    if let chrome = msg.chrome {
      options = options.with(
        chrome: MapOptions.Chrome(
          showsLogo: chrome.showsLogo,
          showsCompass: chrome.showsCompass,
          showsAttribution: chrome.showsAttribution,
          allowsTilting: chrome.allowsTilting
        )
      )
    }
    if let line = msg.routeLineStyle {
      let paint: RouteLineStyle.Paint = line.toColor.map { .gradient(from: color(line.color), to: color($0)) }
        ?? .solid(color(line.color))
      options = options.with(
        routeLineStyle: RouteLineStyle(remaining: paint, completedColor: color(line.completedColor), widthPoints: line.width)
      )
    }
    switch msg.initialFraming {
    case .allFeatures: options = options.with(initialFraming: .allFeatures)
    case .legacyFirstFloor: options = options.with(initialFraming: .legacyFirstFloor)
    }
    switch msg.heading {
    case .course: options = options.with(heading: .course)
    case .compass: options = options.with(heading: .compass)
    case .none: options = options.with(heading: .none)
    }
    options = options.with(language: msg.language)
    if let background = msg.backgroundColor { options = options.with(backgroundColor: color(background)) }
    return options
  }

  // MARK: Geometry and floors

  static func coordinate(_ value: MapMsgCoordinate) -> CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: value.latitude, longitude: value.longitude)
  }

  static func mapCoordinate(_ value: MapMsgCoordinate) -> MapCoordinate {
    MapCoordinate(latitude: value.latitude, longitude: value.longitude)
  }

  static func msg(_ value: CLLocationCoordinate2D) -> MapMsgCoordinate {
    MapMsgCoordinate(latitude: value.latitude, longitude: value.longitude)
  }

  static func msg(_ value: MapCoordinate) -> MapMsgCoordinate {
    MapMsgCoordinate(latitude: value.latitude, longitude: value.longitude)
  }

  static func msg(_ value: ProximiioCoordinate) -> MapMsgCoordinate {
    MapMsgCoordinate(latitude: value.latitude, longitude: value.longitude)
  }

  static func floor(_ value: ProximiioMapSession.Floor) -> MapMsgFloor {
    MapMsgFloor(level: value.key.level, name: value.name)
  }

  static func cameraMode(_ value: MapCameraFollow.Mode) -> MapMsgCameraMode {
    switch value {
    case .free: return .free
    case .follow: return .follow
    case .followWithHeading: return .followWithHeading
    @unknown default: return .free
    }
  }

  static func styleSource(_ value: ProximiioMapSession.StyleSource) -> MapMsgStyleSourceChanged {
    switch value {
    case .pending: return MapMsgStyleSourceChanged(kind: .pending)
    case .cache: return MapMsgStyleSourceChanged(kind: .cache)
    case .organization: return MapMsgStyleSourceChanged(kind: .organization)
    case .offlinePackage(let packageId): return MapMsgStyleSourceChanged(kind: .offlinePackage, detail: packageId)
    case .fallback(let reason): return MapMsgStyleSourceChanged(kind: .fallback, detail: reason)
    @unknown default: return MapMsgStyleSourceChanged(kind: .pending)
    }
  }

  // MARK: Routes

  static func routeOptions(_ value: MapMsgRouteOptions) -> RouteOptions {
    let profile = RouteOptions.Profile(rawValue: value.profile) ?? .pedestrian
    let avoid = Set(RouteOptions.Avoidance.allCases.filter { value.avoid.contains(String(describing: $0)) })
    return RouteOptions(profile: profile, avoid: avoid)
  }

  private static func levelChange(_ value: LevelChange) -> MapMsgLevelChange {
    MapMsgLevelChange(
      featureType: value.featureType,
      fromLevel: value.fromLevel,
      toLevel: value.toLevel,
      coordinate: msg(value.coordinate)
    )
  }

  static func route(_ value: ComputedRoute) -> MapMsgRoute {
    MapMsgRoute(
      coordinates: value.coordinates.map(msg),
      distanceMeters: value.distanceMeters,
      segments: value.segments.map {
        MapMsgSegment(start: msg($0.start), end: msg($0.end), distanceMeters: $0.distanceMeters)
      },
      level: value.level,
      levelChanges: value.levelChanges.map(levelChange),
      instructions: value.instructions.map { instruction in
        var change: MapMsgLevelChange?
        let kind: String
        switch instruction.kind {
        case .levelChange(let value):
          kind = "levelChange"
          change = levelChange(value)
        default:
          kind = String(describing: instruction.kind)
        }
        return MapMsgInstruction(
          kind: kind,
          coordinate: msg(instruction.coordinate),
          distanceMeters: instruction.distanceMeters,
          level: instruction.level,
          durationSeconds: instruction.durationSeconds,
          levelChange: change
        )
      },
      durationSeconds: value.durationSeconds
    )
  }

  static func followRules(_ value: MapMsgFollowRules) -> RouteFollowRules {
    RouteFollowRules(
      arrival: value.arrivalRadiusMeters.map { .fixed(meters: $0) } ?? .venueWalk,
      arrivalDwellSeconds: value.arrivalDwellSeconds,
      offRouteMeters: value.offRouteMeters,
      offRouteFixes: Int(value.offRouteFixes)
    )
  }

  private static func manoeuvre(_ value: RouteManoeuvre) -> MapMsgManoeuvre {
    var change: MapMsgLevelChange?
    let kind: String
    switch value.kind {
    case .levelChange(let ride):
      kind = "levelChange"
      change = MapMsgLevelChange(
        featureType: ride.featureType,
        fromLevel: ride.fromLevel,
        toLevel: ride.toLevel,
        coordinate: msg(ride.coordinate)
      )
    default:
      kind = String(describing: value.kind)
    }
    return MapMsgManoeuvre(
      kind: kind,
      coordinate: msg(value.coordinate),
      level: value.floor.level,
      legMeters: value.legMeters,
      levelChange: change
    )
  }

  static func guidance(_ value: RouteGuidance, text: String?) -> MapMsgGuidance {
    MapMsgGuidance(
      manoeuvre: value.manoeuvre.map(manoeuvre),
      nextManoeuvre: value.nextManoeuvre.map(manoeuvre),
      distanceToManoeuvreMeters: value.distanceToManoeuvreMeters,
      remainingMeters: value.remainingMeters,
      traveledMeters: value.traveledMeters,
      offRouteMeters: value.offRouteMeters,
      isOffRoute: value.isOffRoute,
      hasArrived: value.hasArrived,
      arrivalProgress: value.arrivalProgress,
      text: text
    )
  }

  // MARK: Journeys

  static func stop(_ value: MapMsgStop) -> JourneyStop {
    let kind: JourneyStop.Kind = value.kind == .detour ? .detour : .planned
    let state: JourneyStop.State
    switch value.state {
    case .pending: state = .pending
    case .active: state = .active
    case .reached: state = .reached
    case .done: state = .done
    case .skipped: state = .skipped
    }
    return JourneyStop(
      id: value.id,
      title: value.title,
      coordinate: mapCoordinate(value.coordinate),
      floor: value.level.map { FloorKey(level: $0) },
      poiID: value.poiId,
      group: value.group,
      iconName: value.iconName,
      kind: kind,
      state: state
    )
  }

  static func msg(_ value: JourneyStop) -> MapMsgStop {
    let state: MapMsgStopState
    switch value.state {
    case .pending: state = .pending
    case .active: state = .active
    case .reached: state = .reached
    case .done: state = .done
    case .skipped: state = .skipped
    @unknown default: state = .pending
    }
    return MapMsgStop(
      id: value.id,
      title: value.title,
      coordinate: msg(value.coordinate),
      level: value.floor?.level,
      poiId: value.poiID,
      group: value.group,
      iconName: value.iconName,
      kind: value.kind == .detour ? .detour : .planned,
      state: state
    )
  }

  static func journey(_ value: MapMsgJourney) -> Journey {
    Journey(stops: value.stops.map(stop))
  }

  static func msg(_ value: Journey) -> MapMsgJourney {
    MapMsgJourney(stops: value.stops.map(msg))
  }

  static func rules(_ value: MapMsgJourneyRules) -> JourneyRules {
    JourneyRules(
      advance: value.advanceOnDepartureMeters.map { .onDeparture(meters: $0) } ?? .manual,
      rerouteCooldownSeconds: value.rerouteCooldownSeconds,
      walkingSpeedMetersPerSecond: value.walkingSpeedMetersPerSecond
    )
  }

  static func overview(_ value: JourneyOverview) -> MapMsgOverview {
    MapMsgOverview(
      remainingStopIds: value.remainingStops.map(\.id),
      legs: value.legs.map { leg in
        MapMsgLeg(
          destinationStopId: leg.destinationStopID,
          originStopId: leg.originStopID,
          meters: leg.meters,
          isUnreachable: leg.isUnreachable,
          isActive: leg.isActive,
          durationSeconds: leg.durationSeconds
        )
      },
      remainingMeters: value.remainingMeters,
      etaSeconds: value.etaSeconds,
      activeLegRemainingMeters: value.activeLegRemainingMeters,
      activeLegEtaSeconds: value.activeLegEtaSeconds,
      unmeasuredLegCount: Int64(value.unmeasuredLegCount),
      unreachableStopIds: value.unreachableStopIDs
    )
  }

  static func deviation(_ value: JourneyDeviation) -> MapMsgDeviation {
    MapMsgDeviation(
      episode: Int64(value.episode),
      sinceMs: Int64((value.since.timeIntervalSince1970 * 1000).rounded()),
      distanceMeters: value.distanceMeters,
      isOnRouteFloor: value.isOnRouteFloor
    )
  }

  /// The case name of an enum value, without its associated values.
  static func caseName(_ value: Any) -> String {
    if let label = Mirror(reflecting: value).children.first?.label { return label }
    return String(describing: value)
  }

  static func notice(_ event: JourneyEvent) -> MapMsgJourneyNotice {
    switch event {
    case .leftRoute(let distance): return MapMsgJourneyNotice(kind: "leftRoute", distanceMeters: distance)
    case .farFromRoute(let distance): return MapMsgJourneyNotice(kind: "farFromRoute", distanceMeters: distance)
    case .offRouteTooLong(let duration): return MapMsgJourneyNotice(kind: "offRouteTooLong", durationSeconds: duration)
    case .returnedToRoute: return MapMsgJourneyNotice(kind: "returnedToRoute")
    case .detourOverstayed(let stop, let duration):
      return MapMsgJourneyNotice(kind: "detourOverstayed", stop: msg(stop), durationSeconds: duration)
    case .detourStarted(let stop): return MapMsgJourneyNotice(kind: "detourStarted", stop: msg(stop))
    case .detourEnded(let stop, let completed):
      return MapMsgJourneyNotice(kind: "detourEnded", stop: msg(stop), completed: completed)
    case .stopReached(let stop): return MapMsgJourneyNotice(kind: "stopReached", stop: msg(stop))
    case .stopPassed(let stop): return MapMsgJourneyNotice(kind: "stopPassed", stop: msg(stop))
    case .stopSkipped(let stop): return MapMsgJourneyNotice(kind: "stopSkipped", stop: msg(stop))
    case .legChanged(let stop, let reason):
      return MapMsgJourneyNotice(kind: "legChanged", stop: msg(stop), reason: reason.rawValue)
    case .rerouted(let stop): return MapMsgJourneyNotice(kind: "rerouted", stop: msg(stop))
    case .journeyFinished: return MapMsgJourneyNotice(kind: "journeyFinished")
    @unknown default: return MapMsgJourneyNotice(kind: caseName(event))
    }
  }

  static func origin(_ value: MapMsgOrderOrigin) -> JourneyOrderOrigin {
    value == .visitor ? .visitor : .activeStop
  }

  static func strategy(_ value: MapMsgOrderStrategy) -> JourneyOrderStrategy {
    value == .floorThenGallery ? .floorThenGallery : .quickestWalk
  }
}
#endif
