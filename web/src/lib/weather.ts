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

type HistoricalWeatherRecord = {
  date: string
  highTemperatureF: number
  lowTemperatureF: number
  precipitationInches: number
  humidityPercent: number
  windMph: number
  weatherCode?: number
}

type WeatherLookupPayload = {
  date: string
  latitude?: number
  location?: string
  locationLabel?: string
  longitude?: number
}

const forecastLookaheadDays = 16
const historicalTrendYears = 6

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
  if (shouldUseHistoricalTrend(date)) {
    return lookupHistoricalWeatherTrendDirect({
      date,
      latitude,
      locationLabel,
      longitude,
    })
  }

  const url = new URL('https://api.open-meteo.com/v1/forecast')
  url.searchParams.set('latitude', latitude.toString())
  url.searchParams.set('longitude', longitude.toString())
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
      highTemperatureF: Math.round(maxTemperature),
      lowTemperatureF: Math.round(minTemperature),
      condition: weatherCodeLabel(data.daily?.weather_code?.[dayIndex]),
      isRaining: precipitation > 0.02,
      humidityPercent: averageHumidityForDate(data, date),
      windMph: Math.round(data.daily?.wind_speed_10m_max?.[dayIndex] ?? defaultWeatherInput.windMph),
      source: 'Open-Meteo full-day forecast',
    }
  }

  return lookupHistoricalWeatherTrendDirect({
    date,
    latitude,
    locationLabel,
    longitude,
  })
}

async function lookupHistoricalWeatherTrendDirect({
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
  const trendDates = historicalTrendDates(date)

  if (trendDates.length === 0) {
    throw new Error('No long-range weather trend dates were available.')
  }

  const settledRecords = await Promise.allSettled(
    trendDates.map((trendDate) =>
      lookupHistoricalWeatherRecord({
        date: trendDate,
        latitude,
        longitude,
      }),
    ),
  )
  const records = settledRecords
    .filter((result): result is PromiseFulfilledResult<HistoricalWeatherRecord> =>
      result.status === 'fulfilled',
    )
    .map((result) => result.value)

  if (records.length === 0) {
    throw new Error('No long-range weather trend was available for that location.')
  }

  const highTemperatureF = averageRounded(
    records.map((record) => record.highTemperatureF),
    defaultWeatherInput.highTemperatureF,
  )
  const lowTemperatureF = averageRounded(
    records.map((record) => record.lowTemperatureF),
    defaultWeatherInput.lowTemperatureF,
  )
  const wetDayRate =
    records.filter(
      (record) =>
        record.precipitationInches > 0.02 || isWetWeatherCode(record.weatherCode),
    ).length / records.length

  return {
    location: locationLabel,
    temperatureF: Math.round((highTemperatureF + lowTemperatureF) / 2),
    highTemperatureF,
    lowTemperatureF,
    condition: historicalTrendCondition(records),
    isRaining: wetDayRate >= 0.35,
    humidityPercent: averageRounded(
      records.map((record) => record.humidityPercent),
      defaultWeatherInput.humidityPercent,
    ),
    windMph: averageRounded(
      records.map((record) => record.windMph),
      defaultWeatherInput.windMph,
    ),
    source: `Open-Meteo historical trend (${records.length} years)`,
  }
}

async function lookupHistoricalWeatherRecord({
  date,
  latitude,
  longitude,
}: {
  date: string
  latitude: number
  longitude: number
}): Promise<HistoricalWeatherRecord> {
  const url = new URL('https://archive-api.open-meteo.com/v1/archive')
  url.searchParams.set('latitude', latitude.toString())
  url.searchParams.set('longitude', longitude.toString())
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
    'Historical weather trend lookup failed.',
  )
  const dayIndex = data.daily?.time?.findIndex((time) => time === date) ?? -1

  if (dayIndex < 0) {
    throw new Error(`No historical weather was available for ${date}.`)
  }

  const maxTemperature = data.daily?.temperature_2m_max?.[dayIndex]
  const minTemperature = data.daily?.temperature_2m_min?.[dayIndex]

  if (typeof maxTemperature !== 'number' || typeof minTemperature !== 'number') {
    throw new Error(`Historical weather for ${date} did not include temperatures.`)
  }

  return {
    date,
    highTemperatureF: Math.round(maxTemperature),
    lowTemperatureF: Math.round(minTemperature),
    precipitationInches: numberFromUnknown(data.daily?.precipitation_sum?.[dayIndex], 0),
    humidityPercent: averageHumidityForDate(data, date),
    windMph: Math.round(
      numberFromUnknown(data.daily?.wind_speed_10m_max?.[dayIndex], defaultWeatherInput.windMph),
    ),
    weatherCode: data.daily?.weather_code?.[dayIndex],
  }
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
    highTemperatureF: numberValue(
      data.highTemperatureF,
      numberValue(data.temperatureF, defaultWeatherInput.highTemperatureF),
    ),
    lowTemperatureF: numberValue(
      data.lowTemperatureF,
      numberValue(data.temperatureF, defaultWeatherInput.lowTemperatureF),
    ),
    condition: typeof data.condition === 'string' && data.condition.trim()
      ? data.condition
      : defaultWeatherInput.condition,
    isRaining: Boolean(data.isRaining),
    humidityPercent: numberValue(data.humidityPercent, defaultWeatherInput.humidityPercent),
    windMph: numberValue(data.windMph, defaultWeatherInput.windMph),
    source: typeof data.source === 'string' && data.source.trim() ? data.source : undefined,
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

  const candidates = locationSearchCandidates(trimmedLocation)
  let lastError: unknown

  for (const candidate of candidates) {
    try {
      return await geocodeOpenMeteoLocationCandidate(candidate)
    } catch (error) {
      lastError = error
    }
  }

  throw new Error(
    `No matching location was found for ${trimmedLocation}. Tried: ${candidates.join('; ')}.${
      lastError instanceof Error ? ` Last error: ${lastError.message}` : ''
    }`,
  )
}

async function geocodeOpenMeteoLocationCandidate(location: string): Promise<GeocodingResult> {
  const url = new URL('https://geocoding-api.open-meteo.com/v1/search')
  url.searchParams.set('name', location)
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

function locationSearchCandidates(location: string) {
  const parts = location
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean)
  const lastPart = parts[parts.length - 1]
  const candidates = [
    location.trim(),
    parts.length >= 3 ? `${parts[0]}, ${lastPart}` : '',
    parts.length >= 2 ? `${parts[0]}, ${parts[1]}` : '',
    parts.length >= 3 ? `${parts[1]}, ${lastPart}` : '',
    ...parts,
  ]

  return uniqueStrings(candidates)
}

function uniqueStrings(values: string[]) {
  const seenValues = new Set<string>()
  const uniqueValues: string[] = []

  values.forEach((value) => {
    const trimmedValue = value.trim()
    const key = trimmedValue.toLowerCase()

    if (trimmedValue && !seenValues.has(key)) {
      seenValues.add(key)
      uniqueValues.push(trimmedValue)
    }
  })

  return uniqueValues
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

function averageRounded(values: number[], fallback: number) {
  const finiteValues = values.filter((value) => Number.isFinite(value))

  if (finiteValues.length === 0) {
    return fallback
  }

  return Math.round(finiteValues.reduce((total, value) => total + value, 0) / finiteValues.length)
}

function numberFromUnknown(value: unknown, fallback: number) {
  const parsedValue = Number(value)
  return Number.isFinite(parsedValue) ? parsedValue : fallback
}

function shouldUseHistoricalTrend(date: string) {
  const daysAway = daysFromToday(date)
  return Number.isFinite(daysAway) && daysAway > forecastLookaheadDays
}

function daysFromToday(date: string) {
  const targetDate = parseISODate(date)
  const currentDate = parseISODate(todayISO())

  if (!targetDate || !currentDate) {
    return NaN
  }

  return Math.ceil((targetDate.getTime() - currentDate.getTime()) / 86_400_000)
}

function historicalTrendDates(date: string) {
  const targetDate = parseISODate(date)

  if (!targetDate) {
    return []
  }

  const month = targetDate.getMonth() + 1
  const day = targetDate.getDate()
  const today = parseISODate(todayISO())
  const dates: string[] = []

  if (!today) {
    return dates
  }

  for (
    let year = today.getFullYear() - 1;
    year >= 1940 && dates.length < historicalTrendYears;
    year -= 1
  ) {
    const historicalDate = historicalDateForMonthDay(year, month, day)

    if (historicalDate) {
      dates.push(historicalDate)
    }
  }

  return dates
}

function historicalDateForMonthDay(year: number, month: number, day: number) {
  const candidate = new Date(year, month - 1, day)

  if (
    candidate.getFullYear() === year &&
    candidate.getMonth() === month - 1 &&
    candidate.getDate() === day
  ) {
    return formatLocalDate(candidate)
  }

  if (month === 2 && day === 29) {
    return `${year}-02-28`
  }

  return null
}

function parseISODate(date: string) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date)

  if (!match) {
    return null
  }

  const parsedDate = new Date(
    Number.parseInt(match[1], 10),
    Number.parseInt(match[2], 10) - 1,
    Number.parseInt(match[3], 10),
  )

  if (
    parsedDate.getFullYear() !== Number.parseInt(match[1], 10) ||
    parsedDate.getMonth() !== Number.parseInt(match[2], 10) - 1 ||
    parsedDate.getDate() !== Number.parseInt(match[3], 10)
  ) {
    return null
  }

  return parsedDate
}

function formatLocalDate(date: Date) {
  const month = `${date.getMonth() + 1}`.padStart(2, '0')
  const day = `${date.getDate()}`.padStart(2, '0')
  return `${date.getFullYear()}-${month}-${day}`
}

function historicalTrendCondition(records: HistoricalWeatherRecord[]) {
  const wetDayRate =
    records.filter(
      (record) =>
        record.precipitationInches > 0.02 || isWetWeatherCode(record.weatherCode),
    ).length / records.length
  const stormDayRate = records.filter((record) => isStormWeatherCode(record.weatherCode)).length / records.length
  const snowDayRate = records.filter((record) => isSnowWeatherCode(record.weatherCode)).length / records.length

  if (stormDayRate >= 0.2) {
    return 'Storm Risk'
  }

  if (snowDayRate >= 0.35) {
    return 'Snow Risk'
  }

  if (wetDayRate >= 0.35) {
    return 'Rain Risk'
  }

  return mostCommonWeatherLabel(records.map((record) => weatherCodeLabel(record.weatherCode)))
}

function mostCommonWeatherLabel(labels: string[]) {
  const counts = new Map<string, number>()

  labels.forEach((label) => {
    if (label !== 'Weather') {
      counts.set(label, (counts.get(label) ?? 0) + 1)
    }
  })

  return (
    [...counts.entries()].sort((first, second) => second[1] - first[1])[0]?.[0] ??
    'Historical Trend'
  )
}

function isWetWeatherCode(code?: number) {
  const normalizedCode = Number(code)
  return (
    (normalizedCode >= 51 && normalizedCode <= 67) ||
    (normalizedCode >= 80 && normalizedCode <= 82) ||
    normalizedCode >= 95
  )
}

function isStormWeatherCode(code?: number) {
  const normalizedCode = Number(code)
  return normalizedCode >= 95
}

function isSnowWeatherCode(code?: number) {
  const normalizedCode = Number(code)
  return (normalizedCode >= 71 && normalizedCode <= 77) || normalizedCode === 85 || normalizedCode === 86
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
