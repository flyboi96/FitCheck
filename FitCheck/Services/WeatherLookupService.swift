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
    case missingDailyWeather
    case emptyLocationSearch
    case noMatchingLocation

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The weather request could not be created."
        case .invalidResponse:
            "The weather service response could not be read."
        case .missingCurrentWeather:
            "The weather service did not return current weather."
        case .missingDailyWeather:
            "The weather service did not return daily weather."
        case .emptyLocationSearch:
            "Enter a city or place."
        case .noMatchingLocation:
            "No matching location was found."
        }
    }
}

struct OpenMeteoWeatherClient {
    var session: URLSession = .shared

    func currentWeather(for searchText: String) async throws -> WeatherLookupResult {
        let location = try await geocode(searchText)
        return try await currentWeather(
            latitude: location.latitude,
            longitude: location.longitude,
            locationName: location.displayName
        )
    }

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

    func dailyWeather(for searchText: String, date: Date) async throws -> WeatherLookupResult {
        let location = try await geocode(searchText)
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,rain_sum,wind_speed_10m_max"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "precipitation_unit", value: "inch"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "start_date", value: Self.dateString(for: date)),
            URLQueryItem(name: "end_date", value: Self.dateString(for: date))
        ]

        guard let url = components?.url else {
            throw WeatherLookupError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw WeatherLookupError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(OpenMeteoDailyResponse.self, from: data)
        guard
            let weatherCode = decoded.daily.weatherCode.first,
            let high = decoded.daily.temperatureMax.first,
            let low = decoded.daily.temperatureMin.first,
            let precipitation = decoded.daily.precipitationSum.first,
            let rain = decoded.daily.rainSum.first,
            let windSpeed = decoded.daily.windSpeedMax.first
        else {
            throw WeatherLookupError.missingDailyWeather
        }

        let input = WeatherInput(
            temperatureF: (high + low) / 2,
            isRaining: Self.isWetWeather(code: weatherCode) || rain > 0 || precipitation > 0,
            windMph: windSpeed,
            location: location.displayName
        )

        return WeatherLookupResult(
            input: input,
            condition: Self.conditionName(for: weatherCode),
            sourceDescription: "Open-Meteo forecast",
            fetchedAt: Date()
        )
    }

    private func geocode(_ searchText: String) async throws -> OpenMeteoLocation {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WeatherLookupError.emptyLocationSearch
        }

        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = components?.url else {
            throw WeatherLookupError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw WeatherLookupError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(OpenMeteoGeocodingResponse.self, from: data)
        guard let location = decoded.results?.first else {
            throw WeatherLookupError.noMatchingLocation
        }

        return location
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

    private static func dateString(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return "1970-01-01"
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
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
    private var pendingFallbackSearchText = WeatherLookupFallback.default.name

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func refresh(fallback: WeatherLookupFallback) {
        pendingFallback = fallback
        pendingFallbackSearchText = fallback.name
        errorMessage = nil
        isLoading = true

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .denied, .restricted:
            Task {
                await fetchFallbackSearch(reason: "Using default city")
            }
        @unknown default:
            Task {
                await fetchFallbackSearch(reason: "Using default city")
            }
        }
    }

    func refresh(defaultLocationName: String) {
        let trimmed = defaultLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingFallbackSearchText = trimmed.isEmpty ? WeatherLookupFallback.default.name : trimmed
        errorMessage = nil
        isLoading = true

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .denied, .restricted:
            Task {
                await fetchFallbackSearch(reason: "Using default city")
            }
        @unknown default:
            Task {
                await fetchFallbackSearch(reason: "Using default city")
            }
        }
    }

    func refresh(searchText: String) {
        errorMessage = nil
        isLoading = true

        Task {
            do {
                result = try await weatherClient.currentWeather(for: searchText)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                await fetchFallbackSearch(reason: "Using default city")
            case .notDetermined:
                break
            @unknown default:
                await fetchFallbackSearch(reason: "Using default city")
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
            await fetchFallbackSearch(reason: "Location unavailable; using default city")
        }
    }

    private func fetchFallbackSearch(reason: String) async {
        do {
            result = try await weatherClient.currentWeather(for: pendingFallbackSearchText)
            errorMessage = reason
        } catch {
            await fetchFallback(reason: reason)
            return
        }
        isLoading = false
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
                await fetchFallbackSearch(reason: failureFallbackReason)
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

private struct OpenMeteoGeocodingResponse: Decodable {
    var results: [OpenMeteoLocation]?
}

private struct OpenMeteoDailyResponse: Decodable {
    var daily: Daily

    struct Daily: Decodable {
        var weatherCode: [Int]
        var temperatureMax: [Double]
        var temperatureMin: [Double]
        var precipitationSum: [Double]
        var rainSum: [Double]
        var windSpeedMax: [Double]

        enum CodingKeys: String, CodingKey {
            case weatherCode = "weather_code"
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
            case precipitationSum = "precipitation_sum"
            case rainSum = "rain_sum"
            case windSpeedMax = "wind_speed_10m_max"
        }
    }
}

private struct OpenMeteoLocation: Decodable {
    var name: String
    var latitude: Double
    var longitude: Double
    var country: String?
    var admin1: String?

    var displayName: String {
        [name, admin1, country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
