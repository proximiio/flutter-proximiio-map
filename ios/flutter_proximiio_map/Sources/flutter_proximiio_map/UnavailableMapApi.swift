// Generated from MapMessages.g.swift by tool/generate_unavailable_api.py; do not edit.
import Foundation

/// Answers every map call with one error (no map library, or no SDK instance).
final class UnavailableMapApi: MapHostApi {
  private let error: MapFlutterError

  init(error: MapFlutterError) {
    self.error = error
  }

  func setOptions(options: MapMsgOptions) throws { throw error }
  func cameraState() throws -> MapMsgCameraState { throw error }
  func setCenter(center: MapMsgCoordinate, zoom: Double?, animated: Bool) throws { throw error }
  func setZoom(zoom: Double, animated: Bool) throws { throw error }
  func zoomBy(delta: Double, animated: Bool) throws { throw error }
  func fitCoordinates(coordinates: [MapMsgCoordinate], animated: Bool) throws { throw error }
  func setHeading(degrees: Double?) throws { throw error }
  func recentre(zoom: Double?, withHeading: Bool?) throws { throw error }
  func showVenue(animated: Bool) throws { throw error }
  func floors() throws -> [MapMsgFloor] { throw error }
  func selectedFloor() throws -> Double { throw error }
  func selectFloor(level: Double) throws { throw error }
  func followMyFloor() throws { throw error }
  func setHiddenFeatureIds(ids: [String]) throws { throw error }
  func clearTrail() throws { throw error }
  func showRoute(from: MapMsgCoordinate, fromLevel: Double, to: MapMsgCoordinate, toLevel: Double, options: MapMsgRouteOptions, completion: @escaping (Result<MapMsgRoute, Error>) -> Void) { completion(.failure(error)) }
  func clearRoute() throws { throw error }
  func setGuidanceRules(rules: MapMsgFollowRules?) throws { throw error }
  func instructionText(destinationTitle: String?) throws -> String? { throw error }
  func startJourney(journey: MapMsgJourney, rules: MapMsgJourneyRules, routeOptions: MapMsgRouteOptions, completion: @escaping (Result<Void, Error>) -> Void) { completion(.failure(error)) }
  func endJourney() throws { throw error }
  func journeyState() throws -> MapMsgJourneyState? { throw error }
  func advance(completion: @escaping (Result<Void, Error>) -> Void) { completion(.failure(error)) }
  func skip(completion: @escaping (Result<Void, Error>) -> Void) { completion(.failure(error)) }
  func skipStop(stopId: String, completion: @escaping (Result<Bool, Error>) -> Void) { completion(.failure(error)) }
  func markDone(stopId: String, completion: @escaping (Result<Bool, Error>) -> Void) { completion(.failure(error)) }
  func reopen(stopId: String, completion: @escaping (Result<Bool, Error>) -> Void) { completion(.failure(error)) }
  func activate(stopId: String, completion: @escaping (Result<Bool, Error>) -> Void) { completion(.failure(error)) }
  func detour(stop: MapMsgStop, completion: @escaping (Result<Void, Error>) -> Void) { completion(.failure(error)) }
  func cancelDetour(completion: @escaping (Result<Void, Error>) -> Void) { completion(.failure(error)) }
  func moveStop(stopId: String, toIndex: Int64, completion: @escaping (Result<Void, Error>) -> Void) { completion(.failure(error)) }
  func addStop(stop: MapMsgStop, completion: @escaping (Result<Bool, Error>) -> Void) { completion(.failure(error)) }
  func insertStop(stop: MapMsgStop, index: Int64, completion: @escaping (Result<Bool, Error>) -> Void) { completion(.failure(error)) }
  func removeStop(stopId: String, completion: @escaping (Result<Bool, Error>) -> Void) { completion(.failure(error)) }
  func replaceStop(stop: MapMsgStop, completion: @escaping (Result<Bool, Error>) -> Void) { completion(.failure(error)) }
  func updateJourney(journey: MapMsgJourney, completion: @escaping (Result<Bool, Error>) -> Void) { completion(.failure(error)) }
  func proposeOrder(origin: MapMsgOrderOrigin, pinnedStopIds: [String], strategy: MapMsgOrderStrategy, completion: @escaping (Result<MapMsgProposal?, Error>) -> Void) { completion(.failure(error)) }
  func applyProposal(proposalId: Int64, completion: @escaping (Result<Bool, Error>) -> Void) { completion(.failure(error)) }
  func resumeJourney(completion: @escaping (Result<Void, Error>) -> Void) { completion(.failure(error)) }
  func replanFromHere(pinnedStopIds: [String], completion: @escaping (Result<MapMsgProposal?, Error>) -> Void) { completion(.failure(error)) }
  func setJourneyRouteOptions(options: MapMsgRouteOptions, completion: @escaping (Result<Void, Error>) -> Void) { completion(.failure(error)) }
  func fitActiveLeg(animated: Bool) throws { throw error }
  func fitJourney(animated: Bool) throws { throw error }
  func dispose() throws { throw error }
}
