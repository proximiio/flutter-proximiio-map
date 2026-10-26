// Generated from MapMessages.g.kt by tool/generate_unavailable_api.py; do not edit.
package io.proximi.flutter_proximiio_map

/**
 * Answers every map call with one error (no SDK instance, or no options). `dispose()` succeeds and
 * runs [onDispose], so the notice can release its channels.
 */
internal class UnavailableMapApi(private val error: MapFlutterError, private val onDispose: () -> Unit) : MapHostApi {
  override fun setOptions(options: MapMsgOptions) = throw error
  override fun cameraState(): MapMsgCameraState = throw error
  override fun setCenter(center: MapMsgCoordinate, zoom: Double?, animated: Boolean) = throw error
  override fun setZoom(zoom: Double, animated: Boolean) = throw error
  override fun zoomBy(delta: Double, animated: Boolean) = throw error
  override fun fitCoordinates(coordinates: List<MapMsgCoordinate>, animated: Boolean) = throw error
  override fun setHeading(degrees: Double?) = throw error
  override fun recentre(zoom: Double?, withHeading: Boolean?) = throw error
  override fun showVenue(animated: Boolean) = throw error
  override fun floors(): List<MapMsgFloor> = throw error
  override fun selectedFloor(): Double = throw error
  override fun selectFloor(level: Double) = throw error
  override fun followMyFloor() = throw error
  override fun setHiddenFeatureIds(ids: List<String>) = throw error
  override fun clearTrail() = throw error
  override fun showRoute(from: MapMsgCoordinate, fromLevel: Double, to: MapMsgCoordinate, toLevel: Double, options: MapMsgRouteOptions, callback: (Result<MapMsgRoute>) -> Unit) = callback(Result.failure(error))
  override fun clearRoute() = throw error
  override fun setGuidanceRules(rules: MapMsgFollowRules?) = throw error
  override fun instructionText(destinationTitle: String?): String? = throw error
  override fun startJourney(journey: MapMsgJourney, rules: MapMsgJourneyRules, routeOptions: MapMsgRouteOptions, callback: (Result<Unit>) -> Unit) = callback(Result.failure(error))
  override fun endJourney() = throw error
  override fun journeyState(): MapMsgJourneyState? = throw error
  override fun advance(callback: (Result<Unit>) -> Unit) = callback(Result.failure(error))
  override fun skip(callback: (Result<Unit>) -> Unit) = callback(Result.failure(error))
  override fun skipStop(stopId: String, callback: (Result<Boolean>) -> Unit) = callback(Result.failure(error))
  override fun markDone(stopId: String, callback: (Result<Boolean>) -> Unit) = callback(Result.failure(error))
  override fun reopen(stopId: String, callback: (Result<Boolean>) -> Unit) = callback(Result.failure(error))
  override fun activate(stopId: String, callback: (Result<Boolean>) -> Unit) = callback(Result.failure(error))
  override fun detour(stop: MapMsgStop, callback: (Result<Unit>) -> Unit) = callback(Result.failure(error))
  override fun cancelDetour(callback: (Result<Unit>) -> Unit) = callback(Result.failure(error))
  override fun moveStop(stopId: String, toIndex: Long, callback: (Result<Unit>) -> Unit) = callback(Result.failure(error))
  override fun addStop(stop: MapMsgStop, callback: (Result<Boolean>) -> Unit) = callback(Result.failure(error))
  override fun insertStop(stop: MapMsgStop, index: Long, callback: (Result<Boolean>) -> Unit) = callback(Result.failure(error))
  override fun removeStop(stopId: String, callback: (Result<Boolean>) -> Unit) = callback(Result.failure(error))
  override fun replaceStop(stop: MapMsgStop, callback: (Result<Boolean>) -> Unit) = callback(Result.failure(error))
  override fun updateJourney(journey: MapMsgJourney, callback: (Result<Boolean>) -> Unit) = callback(Result.failure(error))
  override fun proposeOrder(origin: MapMsgOrderOrigin, pinnedStopIds: List<String>, strategy: MapMsgOrderStrategy, callback: (Result<MapMsgProposal?>) -> Unit) = callback(Result.failure(error))
  override fun applyProposal(proposalId: Long, callback: (Result<Boolean>) -> Unit) = callback(Result.failure(error))
  override fun resumeJourney(callback: (Result<Unit>) -> Unit) = callback(Result.failure(error))
  override fun replanFromHere(pinnedStopIds: List<String>, callback: (Result<MapMsgProposal?>) -> Unit) = callback(Result.failure(error))
  override fun setJourneyRouteOptions(options: MapMsgRouteOptions, callback: (Result<Unit>) -> Unit) = callback(Result.failure(error))
  override fun fitActiveLeg(animated: Boolean) = throw error
  override fun fitJourney(animated: Boolean) = throw error
  override fun restartSession() = throw error
  override fun journeyRouteNetworkChanged(callback: (Result<Unit>) -> Unit) = callback(Result.failure(error))
  override fun dispose() = onDispose()
}
