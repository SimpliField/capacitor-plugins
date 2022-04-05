import Foundation
import Capacitor
import GoogleMaps

extension GMSMapViewType {
    static func fromString(mapType: String) -> GMSMapViewType {
        switch mapType {
        case "Normal":
            return .normal
        case "Hybrid":
            return .hybrid
        case "Satellite":
            return .satellite
        case "Terrain":
            return .terrain
        case "None":
            return .none
        default:
            print("CapacitorGoogleMaps Warning: unknown mapView type '\(mapType)'.  Defaulting to normal.")
            return .normal
        }
    }
}

extension CGRect {
    static func fromJSObject(_ jsObject: JSObject) throws -> CGRect {
        guard let width = jsObject["width"] as? Double else {
            throw GoogleMapErrors.invalidArguments("bounds object is missing the required 'width' property")
        }

        guard let height = jsObject["height"] as? Double else {
            throw GoogleMapErrors.invalidArguments("bounds object is missing the required 'height' property")
        }

        guard let x = jsObject["x"] as? Double else {
            throw GoogleMapErrors.invalidArguments("bounds object is missing the required 'x' property")
        }

        guard let y = jsObject["y"] as? Double else {
            throw GoogleMapErrors.invalidArguments("bounds object is missing the required 'y' property")
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }
}

@objc(CapacitorGoogleMapsPlugin)
public class CapacitorGoogleMapsPlugin: CAPPlugin, GMSMapViewDelegate {
    private var maps = [String: Map]()
    private var isInitialized = false

    func checkLocationPermission() -> String {
        let locationState: String

        switch CLLocationManager.authorizationStatus() {
        case .notDetermined:
            locationState = "prompt"
        case .restricted, .denied:
            locationState = "denied"
        case .authorizedAlways, .authorizedWhenInUse:
            locationState = "granted"
        @unknown default:
            locationState = "prompt"
        }

        return locationState
    }

    @objc func create(_ call: CAPPluginCall) {
        do {
            if !isInitialized {
                guard let apiKey = call.getString("apiKey") else {
                    throw GoogleMapErrors.invalidAPIKey
                }

                GMSServices.provideAPIKey(apiKey)
                isInitialized = true
            }

            guard let id = call.getString("id") else {
                throw GoogleMapErrors.invalidMapId
            }

            guard let configObj = call.getObject("config") else {
                throw GoogleMapErrors.invalidArguments("config object is missing")
            }

            let forceCreate = call.getBool("forceCreate", false)

            let config = try GoogleMapConfig(fromJSObject: configObj)

            if self.maps[id] != nil {
                if !forceCreate {
                    call.resolve()
                    return
                }

                let removedMap = self.maps.removeValue(forKey: id)
                removedMap?.destroy()
            }

            DispatchQueue.main.sync {
                let newMap = Map(id: id, config: config, delegate: self)
                self.maps[id] = newMap
            }

            call.resolve()
        } catch {
            handleError(call, error: error)
        }
    }

    @objc func destroy(_ call: CAPPluginCall) {
        do {
            guard let id = call.getString("id") else {
                throw GoogleMapErrors.invalidMapId
            }

            guard let removedMap = self.maps.removeValue(forKey: id) else {
                throw GoogleMapErrors.mapNotFound
            }

            removedMap.destroy()
            call.resolve()
        } catch {
            handleError(call, error: error)
        }
    }

    @objc func addMarker(_ call: CAPPluginCall) {
        do {
            guard let id = call.getString("id") else {
                throw GoogleMapErrors.invalidMapId
            }

            guard let markerObj = call.getObject("marker") else {
                throw GoogleMapErrors.invalidArguments("marker object is missing")
            }

            let marker = try Marker(fromJSObject: markerObj)

            guard let map = self.maps[id] else {
                throw GoogleMapErrors.mapNotFound
            }

            let markerId = try map.addMarker(marker: marker)

            call.resolve(["id": String(markerId)])

        } catch {
            handleError(call, error: error)
        }
    }

    @objc func addMarkers(_ call: CAPPluginCall) {
        do {
            guard let id = call.getString("id") else {
                throw GoogleMapErrors.invalidMapId
            }

            guard let markerObjs = call.getArray("markers") as? [JSObject] else {
                throw GoogleMapErrors.invalidArguments("markers array is missing")
            }

            if markerObjs.isEmpty {
                throw GoogleMapErrors.invalidArguments("markers requires at least one marker")
            }

            guard let map = self.maps[id] else {
                throw GoogleMapErrors.mapNotFound
            }

            var markers: [Marker] = []

            try markerObjs.forEach { marker in
                let marker = try Marker(fromJSObject: marker)
                markers.append(marker)
            }

            let ids = try map.addMarkers(markers: markers)

            call.resolve(["ids": ids.map({ id in
                return String(id)
            })])

        } catch {
            handleError(call, error: error)
        }
    }

    @objc func removeMarkers(_ call: CAPPluginCall) {
        do {
            guard let id = call.getString("id") else {
                throw GoogleMapErrors.invalidMapId
            }

            guard let markerIdStrings = call.getArray("markerIds") as? [String] else {
                throw GoogleMapErrors.invalidArguments("markerIds are invalid or missing")
            }

            if markerIdStrings.isEmpty {
                throw GoogleMapErrors.invalidArguments("markerIds requires at least one marker id")
            }

            let ids: [Int] = try markerIdStrings.map { idString in
                guard let markerId = Int(idString) else {
                    throw GoogleMapErrors.invalidArguments("markerIds are invalid or missing")
                }

                return markerId
            }

            guard let map = self.maps[id] else {
                throw GoogleMapErrors.mapNotFound
            }

            try map.removeMarkers(ids: ids)

            call.resolve()
        } catch {
            handleError(call, error: error)
        }
    }

    @objc func removeMarker(_ call: CAPPluginCall) {
        do {
            guard let id = call.getString("id") else {
                throw GoogleMapErrors.invalidMapId
            }

            guard let markerIdString = call.getString("markerId") else {
                throw GoogleMapErrors.invalidArguments("markerId is invalid or missing")
            }

            guard let markerId = Int(markerIdString) else {
                throw GoogleMapErrors.invalidArguments("markerId is invalid or missing")
            }

            guard let map = self.maps[id] else {
                throw GoogleMapErrors.mapNotFound
            }

            try map.removeMarker(id: markerId)

            call.resolve()

        } catch {
            handleError(call, error: error)
        }
    }

    @objc func setCamera(_ call: CAPPluginCall) {
        do {
            guard let id = call.getString("id") else {
                throw GoogleMapErrors.invalidMapId
            }

            guard let map = self.maps[id] else {
                throw GoogleMapErrors.mapNotFound
            }

            guard let configObj = call.getObject("config") else {
                throw GoogleMapErrors.invalidArguments("config object is missing")
            }

            let config = try GoogleMapCameraConfig(fromJSObject: configObj)

            try map.setCamera(config: config)

            call.resolve()
        } catch {
            handleError(call, error: error)
        }
    }

    @objc func setMapType(_ call: CAPPluginCall) {
        do {
            guard let id = call.getString("id") else {
                throw GoogleMapErrors.invalidMapId
            }

            guard let map = self.maps[id] else {
                throw GoogleMapErrors.mapNotFound
            }

            guard let mapTypeString = call.getString("mapType") else {
                throw GoogleMapErrors.invalidArguments("mapType is missing")
            }

            let mapType = GMSMapViewType.fromString(mapType: mapTypeString)

            try map.setMapType(mapType: mapType)

            call.resolve()
        } catch {
            handleError(call, error: error)
        }
    }

    @objc func enableIndoorMaps(_ call: CAPPluginCall) {
        do {
            guard let id = call.getString("id") else {
                throw GoogleMapErrors.invalidMapId
            }

            guard let map = self.maps[id] else {
                throw GoogleMapErrors.mapNotFound
            }

            guard let enabled = call.getBool("enabled") else {
                throw GoogleMapErrors.invalidArguments("enabled is missing")
            }

            try map.enableIndoorMaps(enabled: enabled)

            call.resolve()
        } catch {
            handleError(call, error: error)
        }
    }

    @objc func enableTrafficLayer(_ call: CAPPluginCall) {
        do {
            guard let id = call.getString("id") else {
                throw GoogleMapErrors.invalidMapId
            }

            guard let map = self.maps[id] else {
                throw GoogleMapErrors.mapNotFound
            }

            guard let enabled = call.getBool("enabled") else {
                throw GoogleMapErrors.invalidArguments("enabled is missing")
            }

            try map.enableTrafficLayer(enabled: enabled)

            call.resolve()
        } catch {
            handleError(call, error: error)
        }
    }

    @objc func enableAccessibilityElements(_ call: CAPPluginCall) {
        do {
            guard let id = call.getString("id") else {
                throw GoogleMapErrors.invalidMapId
            }

            guard let map = self.maps[id] else {
                throw GoogleMapErrors.mapNotFound
            }

            guard let enabled = call.getBool("enabled") else {
                throw GoogleMapErrors.invalidArguments("enabled is missing")
            }

            try map.enableAccessibilityElements(enabled: enabled)

            call.resolve()
        } catch {
            handleError(call, error: error)
        }
    }

    @objc func setPadding(_ call: CAPPluginCall) {
        do {
            guard let id = call.getString("id") else {
                throw GoogleMapErrors.invalidMapId
            }

            guard let map = self.maps[id] else {
                throw GoogleMapErrors.mapNotFound
            }

            guard let configObj = call.getObject("padding") else {
                throw GoogleMapErrors.invalidArguments("padding is missing")
            }

            let padding = try GoogleMapPadding.init(fromJSObject: configObj)

            try map.setPadding(padding: padding)

            call.resolve()
        } catch {
            handleError(call, error: error)
        }
    }

    @objc func enableCurrentLocation(_ call: CAPPluginCall) {
        do {
            guard let id = call.getString("id") else {
                throw GoogleMapErrors.invalidMapId
            }

            guard let map = self.maps[id] else {
                throw GoogleMapErrors.mapNotFound
            }

            guard let enabled = call.getBool("enabled") else {
                throw GoogleMapErrors.invalidArguments("enabled is missing")
            }

            if enabled && checkLocationPermission() != "granted" {
                throw GoogleMapErrors.permissionsDeniedLocation
            }

            try map.enableCurrentLocation(enabled: enabled)

            call.resolve()
        } catch {
            handleError(call, error: error)
        }
    }

    @objc func enableClustering(_ call: CAPPluginCall) {
        do {
            guard let id = call.getString("id") else {
                throw GoogleMapErrors.invalidMapId
            }

            guard let map = self.maps[id] else {
                throw GoogleMapErrors.mapNotFound
            }

            map.enableClustering()
            call.resolve()

        } catch {
            handleError(call, error: error)
        }
    }

    @objc func disableClustering(_ call: CAPPluginCall) {
        do {
            guard let id = call.getString("id") else {
                throw GoogleMapErrors.invalidMapId
            }

            guard let map = self.maps[id] else {
                throw GoogleMapErrors.mapNotFound
            }

            map.disableClustering()
            call.resolve()
        } catch {
            handleError(call, error: error)
        }
    }

    @objc func onScroll(_ call: CAPPluginCall) {
        do {
            guard let id = call.getString("id") else {
                throw GoogleMapErrors.invalidMapId
            }

            guard let map = self.maps[id] else {
                throw GoogleMapErrors.mapNotFound
            }

            guard let frame = call.getObject("frame") else {
                throw GoogleMapErrors.invalidArguments("frame is missing")
            }

            guard let bounds = call.getObject("mapBounds") else {
                throw GoogleMapErrors.invalidArguments("mapBounds is missing")
            }

            let frameRect = try CGRect.fromJSObject(frame)
            let boundsRect = try CGRect.fromJSObject(bounds)

            map.updateRender(frame: frameRect, mapBounds: boundsRect)

            call.resolve()
        } catch {
            handleError(call, error: error)
        }
    }

    private func handleError(_ call: CAPPluginCall, error: Error) {
        let errObject = getErrorObject(error)
        call.reject(errObject.message, "\(errObject.code)", error, [:])
    }

}