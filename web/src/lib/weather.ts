import { defaultWeatherInput, type WeatherInput } from './outfits'
import { getAIProxySettings } from './settings'

type GeocodingResult = {
  latitude: number
  longitude: number
  name: string
  admin1?: string
  country?: string
}

type OpenMeteoForecast = {
  current?: {
    temperature_2m?: number
    relative_humidity_2m?: number
    precipitation?: number
    rain?: number
    weather_code?: number
    wind_speed_10m?: number
  }
  daily?: {
    time?: string[]
    weather_code?: number[]
    temperature_2m_max?: number[]
    temperature_2m_min?: number[]
    precipitation_sum?: number[]
    wind_speed_10m_max?: number[]
  }
  hourly?: {
    time?: string[]
    relative_humidity_2m?: number[]
  }
}

type WeatherLookupPayload = {
  date: string
  latitude?: number
  location?: string
  locationLabel?: string
  longitude?: number
}

export async function lookupWeatherByLocation(location: string, date = todayISO()) {
  const trimmedLocation = location.trim()

  try {
    const place = await geocodeLocation(trimmedLocation)
    return lookupWeatherByCoordinatesDirect({
      date,
      latitude: place.latitude,
      locationLabel: locationLabel(place),
      longitude: place.longitude,
    })
  } catch (error) {
    return lookupWeatherViaProxy(
      {
        date,
        location: trimmedLocation,
      },
      error,
    )
  }
}

export function todayWeatherDate() {
  return todayISO()
}

export async function lookupWeatherAtCurrentLocation(date = todayISO()) {
  const position = await currentPosition()
  return lookupWeatherByCoordinates({
    date,
    latitude: position.coords.latitude,
    locationLabel: 'Current Location',
    longitude: position.coords.longitude,
  })
}

export async function lookupWeatherByCoordinates({
  date,
  latitude,
  locationLabel,
  longitude,
}: {
  date: string
  latitude: number
  locationLabel: string
  longitude: number
}): Promise<WeatherInput> {
  try {
    return await lookupWeatherByCoordinatesDirect({
      date,
      latitude,
      locationLabel,
      longitude,
    })
  } catch (error) {
    return lookupWeatherViaProxy(
      {
        date,
        latitude,
        locationLabel,
        longitude,
      },
      error,
    )
  }
}

async function lookupWeatherByCoordinatesDirect({
  date,
  latitude,
  locationLabel,
  longitude,
}: {
  date: string
  latitude: number
  locationLabel: string
  longitude: number
}): Promise<WeatherInput> {
  const url = new URL('https://api.open-meteo.com/v1/forecast')
  url.searchParams.set('latitude', latitude.toString())
  url.searchParams.set('longitude', longitude.toString())
  url.searchParams.set(
    'current',
    'temperature_2m,relative_humidity_2m,precipitation,rain,weather_code,wind_speed_10m',
  )
  url.searchParams.set(
    'daily',
    'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,wind_speed_10m_max',
  )
  url.searchParams.set('hourly', 'relative_humidity_2m')
  url.searchParams.set('temperature_unit', 'fahrenheit')
  url.searchParams.set('wind_speed_unit', 'mph')
  url.searchParams.set('precipitation_unit', 'inch')
  url.searchParams.set('timezone', 'auto')
  url.searchParams.set('start_date', date)
  url.searchParams.set('end_date', date)

  const data = await fetchWeatherJSON<OpenMeteoForecast & { reason?: string }>(
    url,
    'Weather lookup failed.',
  )

  const dayIndex = data.daily?.time?.findIndex((time) => time === date) ?? -1

  if (dayIndex >= 0) {
    const maxTemperature = data.daily?.temperature_2m_max?.[dayIndex] ?? defaultWeatherInput.temperatureF
    const minTemperature = data.daily?.temperature_2m_min?.[dayIndex] ?? maxTemperature
    const precipitation = data.daily?.precipitation_sum?.[dayIndex] ?? 0

    return {
      location: locationLabel,
      temperatureF: Math.round((maxTemperature + minTemperature) / 2),
      condition: weatherCodeLabel(data.daily?.weather_code?.[dayIndex]),
      isRaining: precipitation > 0.02,
      humidityPercent: averageHumidityForDate(data, date),
      windMph: Math.round(data.daily?.wind_speed_10m_max?.[dayIndex] ?? defaultWeatherInput.windMph),
    }
  }

  if (date === todayISO() && data.current?.temperature_2m != null) {
    return {
      location: locationLabel,
      temperatureF: Math.round(data.current.temperature_2m),
      condition: weatherCodeLabel(data.current.weather_code),
      isRaining: Number(data.current.precipitation ?? data.current.rain ?? 0) > 0,
      humidityPercent: Math.round(data.current.relative_humidity_2m ?? defaultWeatherInput.humidityPercent),
      windMph: Math.round(data.current.wind_speed_10m ?? defaultWeatherInput.windMph),
    }
  }

  throw new Error('No forecast was available for that date.')
}

async function lookupWeatherViaProxy(
  payload: WeatherLookupPayload,
  directError: unknown,
): Promise<WeatherInput> {
  const directMessage = weatherErrorMessage(directError, 'Direct weather lookup failed.')
  const { proxyToken, proxyUrl } = getAIProxySettings()
  const baseURL = proxyUrl.trim().replace(/\/+$/, '')

  if (!baseURL) {
    throw new Error(
      `${directMessage} Manual weather still works. Add your Render proxy URL in More > AI Proxy to enable fallback weather lookup.`,
    )
  }

  const configurationProblem = proxyURLConfigurationProblem(baseURL)
  if (configurationProblem) {
    throw new Error(`${directMessage} ${configurationProblem}`)
  }

  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  }

  if (proxyToken.trim()) {
    headers['X-FitCheck-Token'] = proxyToken.trim()
  }

  let response: Response

  try {
    response = await fetch(`${baseURL}/weather-lookup`, {
      body: JSON.stringify(payload),
      headers,
      method: 'POST',
    })
  } catch (error) {
    throw new Error(
      `Weather lookup failed in Safari and through the proxy. Browser: ${directMessage}. Proxy: ${weatherErrorMessage(error, 'Failed to fetch')}. You can still enter temp, condition, humidity, wind, and rain manually.`,
      { cause: error },
    )
  }

  const data = (await response.json().catch(() => ({}))) as Partial<WeatherInput> & {
    error?: string
  }

  if (!response.ok) {
    throw new Error(
      `Weather lookup failed. Browser: ${directMessage}. Proxy: ${data.error || 'Weather proxy failed.'} You can still enter weather manually.`,
    )
  }

  return normalizeWeatherInput(data)
}

function normalizeWeatherInput(data: Partial<WeatherInput>): WeatherInput {
  return {
    location: typeof data.location === 'string' && data.location.trim()
      ? data.location
      : defaultWeatherInput.location,
    temperatureF: numberValue(data.temperatureF, defaultWeatherInput.temperatureF),
    condition: typeof data.condition === 'string' && data.condition.trim()
      ? data.condition
      : defaultWeatherInput.condition,
    isRaining: Boolean(data.isRaining),
    humidityPercent: numberValue(data.humidityPercent, defaultWeatherInput.humidityPercent),
    windMph: numberValue(data.windMph, defaultWeatherInput.windMph),
  }
}

function numberValue(value: unknown, fallback: number) {
  const number = Number(value)
  return Number.isFinite(number) ? Math.round(number) : fallback
}

function weatherErrorMessage(error: unknown, fallback: string) {
  return error instanceof Error && error.message.trim() ? error.message : fallback
}

function proxyURLConfigurationProblem(baseURL: string) {
  if (typeof window === 'undefined') {
    return ''
  }

  const pageHostname = window.location.hostname
  const pageIsLocal = ['localhost', '127.0.0.1', '::1'].includes(pageHostname)
  const proxyIsLocal = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(?::|\/|$)/i.test(baseURL)

  if (!pageIsLocal && proxyIsLocal) {
    return 'Your saved proxy URL points to localhost, but this PWA is running from the web. Set More > AI Proxy to your Render HTTPS URL, then save and retry.'
  }

  if (window.location.protocol === 'https:' && baseURL.startsWith('http://') && !proxyIsLocal) {
    return 'This PWA is loaded over HTTPS, so the proxy URL also needs to use HTTPS.'
  }

  return ''
}

async function geocodeLocation(location: string): Promise<GeocodingResult> {
  const trimmedLocation = location.trim()

  if (!trimmedLocation) {
    throw new Error('Enter a city or location first.')
  }

  const url = new URL('https://geocoding-api.open-meteo.com/v1/search')
  url.searchParams.set('name', trimmedLocation)
  url.searchParams.set('count', '1')
  url.searchParams.set('language', 'en')
  url.searchParams.set('format', 'json')

  const data = await fetchWeatherJSON<{ results?: GeocodingResult[]; reason?: string }>(
    url,
    'Location lookup failed.',
  )

  const result = data.results?.[0]

  if (!result) {
    throw new Error('No matching location was found.')
  }

  return result
}

function currentPosition() {
  if (!navigator.geolocation) {
    throw new Error('Location services are not available in this browser.')
  }

  return new Promise<GeolocationPosition>((resolve, reject) => {
    navigator.geolocation.getCurrentPosition(resolve, reject, {
      enableHighAccuracy: false,
      maximumAge: 15 * 60 * 1000,
      timeout: 12_000,
    })
  })
}

async function fetchWeatherJSON<T>(url: URL, fallbackMessage: string): Promise<T> {
  let response: Response

  try {
    response = await fetch(url, {
      signal: AbortSignal.timeout(12_000),
    })
  } catch (error) {
    throw new Error(`${fallbackMessage} ${weatherErrorMessage(error, 'fetch failed')}`, {
      cause: error,
    })
  }

  const data = (await response.json().catch(() => ({}))) as T & { reason?: string }

  if (!response.ok) {
    throw new Error(data.reason || fallbackMessage)
  }

  return data
}

function averageHumidityForDate(data: OpenMeteoForecast, date: string) {
  const humidityValues =
    data.hourly?.time
      ?.map((time, index) =>
        time.startsWith(date) ? data.hourly?.relative_humidity_2m?.[index] : undefined,
      )
      .filter((value): value is number => typeof value === 'number') ?? []

  if (humidityValues.length === 0) {
    return defaultWeatherInput.humidityPercent
  }

  return Math.round(
    humidityValues.reduce((total, value) => total + value, 0) / humidityValues.length,
  )
}

function locationLabel(place: GeocodingResult) {
  return [place.name, place.admin1, place.country].filter(Boolean).join(', ')
}

function todayISO() {
  const now = new Date()
  const month = `${now.getMonth() + 1}`.padStart(2, '0')
  const day = `${now.getDate()}`.padStart(2, '0')
  return `${now.getFullYear()}-${month}-${day}`
}

function weatherCodeLabel(code?: number) {
  switch (code) {
    case 0:
      return 'Clear'
    case 1:
    case 2:
    case 3:
      return 'Partly Cloudy'
    case 45:
    case 48:
      return 'Fog'
    case 51:
    case 53:
    case 55:
    case 56:
    case 57:
      return 'Drizzle'
    case 61:
    case 63:
    case 65:
    case 66:
    case 67:
      return 'Rain'
    case 71:
    case 73:
    case 75:
    case 77:
      return 'Snow'
    case 80:
    case 81:
    case 82:
      return 'Rain Showers'
    case 85:
    case 86:
      return 'Snow Showers'
    case 95:
    case 96:
    case 99:
      return 'Storm'
    default:
      return 'Weather'
  }
}
