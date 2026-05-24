import CoreLocation
import Foundation

struct WeatherLookupFallback: Equatable {
    var name: String
    var latitude: Double
    var longitude: Double

    static let `default` = WeatherLookupFallback(
        name: "New York",
        latitude: 40.7128,
        longitude: -74.0060
    )
}

struct WeatherLookupResult: Equatable {
    var input: WeatherInput
    var condition: String
    var sourceDescription: String
    var fetchedAt: Date
}

enum WeatherLookupError: LocalizedError {
    case invalidURL
    case invalidResponse
    case missingCurrentWeather

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The weather request could not be created."
        case .invalidResponse:
            "The weather service response could not be read."
        case .missingCurrentWeather:
            "The weather service did not return current weather."
        }
    }
}

struct OpenMeteoWeatherClient {
    var session: URLSession = .shared

    func currentWeather(latitude: Double, longitude: Double, locationName: String) async throws -> WeatherLookupResult {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,precipitation,rain,weather_code,wind_speed_10m"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "precipitation_unit", value: "inch"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components?.url else {
            throw WeatherLookupError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw WeatherLookupError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let current = decoded.current
        let isRaining = Self.isWetWeather(code: current.weatherCode) || current.rain > 0 || current.precipitation > 0
        let input = WeatherInput(
            temperatureF: current.temperature,
            isRaining: isRaining,
            windMph: current.windSpeed,
            location: locationName
        )

        return WeatherLookupResult(
            input: input,
            condition: Self.conditionName(for: current.weatherCode),
            sourceDescription: "Open-Meteo",
            fetchedAt: Date()
        )
    }

    private static func isWetWeather(code: Int) -> Bool {
        switch code {
        case 51...67, 71...77, 80...82, 85...86, 95...99:
            true
        default:
            false
        }
    }

    private static func conditionName(for code: Int) -> String {
        switch code {
        case 0:
            "Clear"
        case 1...3:
            "Cloudy"
        case 45, 48:
            "Fog"
        case 51...57:
            "Drizzle"
        case 61...67, 80...82:
            "Rain"
        case 71...77, 85...86:
            "Snow"
        case 95...99:
            "Storm"
        default:
            "Weather"
        }
    }
}

@MainActor
final class WeatherLookupController: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var result: WeatherLookupResult?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let locationManager = CLLocationManager()
    private let weatherClient = OpenMeteoWeatherClient()
    private var pendingFallback: WeatherLookupFallback = .default

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func refresh(fallback: WeatherLookupFallback) {
        pendingFallback = fallback
        errorMessage = nil
        isLoading = true

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .denied, .restricted:
            Task {
                await fetchFallback(reason: "Using fallback location")
            }
        @unknown default:
            Task {
                await fetchFallback(reason: "Using fallback location")
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                await fetchFallback(reason: "Using fallback location")
            case .notDetermined:
                break
            @unknown default:
                await fetchFallback(reason: "Using fallback location")
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            await fetchWeather(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                locationName: "Current location",
                failureFallbackReason: "Location weather failed; using fallback"
            )
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            await fetchFallback(reason: "Location unavailable; using fallback")
        }
    }

    private func fetchFallback(reason: String) async {
        await fetchWeather(
            latitude: pendingFallback.latitude,
            longitude: pendingFallback.longitude,
            locationName: pendingFallback.name,
            failureFallbackReason: nil,
            statusPrefix: reason
        )
    }

    private func fetchWeather(
        latitude: Double,
        longitude: Double,
        locationName: String,
        failureFallbackReason: String?,
        statusPrefix: String? = nil
    ) async {
        do {
            let weather = try await weatherClient.currentWeather(
                latitude: latitude,
                longitude: longitude,
                locationName: locationName
            )
            if let statusPrefix {
                errorMessage = statusPrefix
            }
            result = weather
        } catch {
            if let failureFallbackReason {
                await fetchFallback(reason: failureFallbackReason)
                return
            }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct OpenMeteoResponse: Decodable {
    var current: Current

    struct Current: Decodable {
        var temperature: Double
        var precipitation: Double
        var rain: Double
        var weatherCode: Int
        var windSpeed: Double

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case precipitation
            case rain
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
        }
    }
}
