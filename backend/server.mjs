import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { Blob } from "node:buffer";

function loadDotEnv(filePath = ".env") {
  const fullPath = path.resolve(process.cwd(), filePath);

  if (!fs.existsSync(fullPath)) {
    return;
  }

  const lines = fs.readFileSync(fullPath, "utf8").split(/\r?\n/);

  for (const line of lines) {
    const trimmed = line.trim();

    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }

    const equalsIndex = trimmed.indexOf("=");

    if (equalsIndex === -1) {
      continue;
    }

    const key = trimmed.slice(0, equalsIndex).trim();
    let value = trimmed.slice(equalsIndex + 1).trim();

    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    if (!process.env[key]) {
      process.env[key] = value;
    }
  }
}

loadDotEnv();

const port = Number(process.env.PORT ?? 8787);
const host = process.env.HOST ?? "0.0.0.0";
const openAIKey = process.env.OPENAI_API_KEY;
const openAIModel = process.env.OPENAI_MODEL ?? "gpt-5-mini";
const openAIVisionModel = process.env.OPENAI_VISION_MODEL ?? openAIModel;
const openAIImageModel = process.env.OPENAI_IMAGE_MODEL ?? "gpt-image-1";
const requestedImageQuality = String(process.env.OPENAI_IMAGE_QUALITY ?? "medium").toLowerCase();
const openAIImageQuality = ["low", "medium", "high", "auto"].includes(requestedImageQuality)
  ? requestedImageQuality
  : "medium";
const proxyToken = process.env.FITCHECK_PROXY_TOKEN ?? "";
const maxBodyBytes = 10_000_000;
const clothingCategories = [
  "shirt",
  "blouse",
  "pants",
  "shorts",
  "dress",
  "skirt",
  "shoes",
  "heels",
  "flats",
  "jacket",
  "sweater",
  "activewear",
  "underwear",
  "socks",
  "belt",
  "watch",
  "jewelry",
  "accessory",
  "bag",
  "purse",
  "other"
];

const responseSchema = {
  type: "object",
  additionalProperties: false,
  required: ["itemIDs", "rationale", "cautions"],
  properties: {
    itemIDs: {
      type: "array",
      items: { type: "string" },
      minItems: 3,
      maxItems: 8
    },
    rationale: {
      type: "string"
    },
    cautions: {
      type: "array",
      items: { type: "string" },
      maxItems: 5
    }
  }
};

const clothingDescriptionSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "name",
    "category",
    "color",
    "material",
    "pattern",
    "formalityLevel",
    "weatherSuitability",
    "occasionSuitability",
    "activitySuitability",
    "notes"
  ],
  properties: {
    name: {
      type: "string"
    },
    category: {
      type: "string",
      enum: clothingCategories
    },
    color: {
      type: "string"
    },
    material: {
      type: "string"
    },
    pattern: {
      type: "string"
    },
    formalityLevel: {
      type: "integer",
      minimum: 1,
      maximum: 5
    },
    weatherSuitability: {
      type: "string"
    },
    occasionSuitability: {
      type: "string"
    },
    activitySuitability: {
      type: "string"
    },
    notes: {
      type: "string"
    }
  }
};

const styleProfileSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "styleDescription",
    "favoriteLooks",
    "preferredColors",
    "preferredFit",
    "dislikedCombinations",
    "rules",
    "boldness"
  ],
  properties: {
    styleDescription: { type: "string" },
    favoriteLooks: { type: "string" },
    preferredColors: { type: "string" },
    preferredFit: { type: "string" },
    dislikedCombinations: { type: "string" },
    rules: { type: "string" },
    boldness: {
      type: "integer",
      minimum: 1,
      maximum: 5
    }
  }
};

const instructions = `
You are FitCheck's private outfit reviewer. Review outfits for a single user's real closet.
Use practical, modern personal style judgment: color harmony, silhouette, material, selected outfit context,
weather, location, user style preferences, outfit rotation, trends that fit the user's taste, and prior negative feedback.

Rules:
- Only return item IDs that were provided in the closet payload.
- Prefer the candidate outfit if it is solid; suggest swaps only when the candidate has a clear issue.
- Never invent clothing items or duplicate a closet item beyond its saved quantity.
- Do not chase trends when they conflict with the user's saved feedback, body of preferences, or practical needs.
- The app starts with these default outfit contexts: Work, Travel, Casual, Coastal Casual, Lounge, Going Out, Exploring, Outdoor Recreation, Lifting, Running.
- The user may rename, remove, or add custom contexts. Honor the provided contextLabel and contextDefinition as the selected context's meaning.
- Do not treat hot, cold, rainy, snowy, humid, or windy as outfit contexts. Those are weather inputs only.
- Interpret the selected context first. Use weather afterward to adjust fabric, layering, footwear, and outerwear without changing the selected context.
- Treat saved style rules as hard constraints. If the user says collared shirts need belts, include a belt with collared shirts and belt-loop bottoms.
- For work, office, pilot, flight, or business contexts, do not choose shorts, sweatpants, joggers, track pants, exercise bottoms, or athletic gym clothes unless the user's profile explicitly allows that exact exception.
- Work outfits must have a structured work top, tailored bottom, and polished footwear. Do not approve Crocs, clogs, slides, flip-flops, slippers, running shoes, gym shoes, or casual sandals for work.
- Do not pair a collared shirt, button-down shirt, work shirt, blazer, or other polished top with lounge pants, sweatpants, joggers, pajama pants, or track pants.
- Do not pair sweatpants or joggers with leather boots. Keep sweatpants with athletic or casual sneakers and only in casual/exercise contexts.
- Only include a belt when the outfit has pants or shorts that realistically have belt loops. Never add a belt to sweatpants, joggers, track pants, exercise shorts, leggings, or any bottom that cannot physically take a belt.
- Crocs, foam clogs, slides, and slippers are casual-only and should usually be rejected unless the user explicitly asks for that kind of casual footwear.
- Coastal Casual is distinct from Casual: it allows relaxed beach-town pieces such as flip flops, shorts, tanks, T-shirts, linen, cotton, and swimsuit-adjacent casual pieces.
- For Lifting or Running contexts, do not add belts, dress accessories, or non-exercise clothing. Prefer running socks and running shoes for Running; prefer training shoes and lifting/training socks for Lifting.
- Keep the rationale concise and specific.
- Put risks or caveats in cautions, not the rationale.
`;

const clothingDescriptionInstructions = `
You are FitCheck's private closet import assistant. Describe one clothing item from a user's photo.
Use the optional user description as context, but trust the image when it clearly conflicts.

Rules:
- Return one closet item, not a full outfit.
- The name should be concise and useful in a closet, like "navy merino wool sweater" or "white leather sneakers".
- Put color, material, pattern, and clothing type in the name when visible or strongly implied.
- Return material separately too, such as cotton, merino wool, leather, linen, denim, or synthetic blend.
- Choose category only from the provided enum.
- Use comma-separated tags for weatherSuitability, occasionSuitability, and activitySuitability.
- Prefer practical tags such as hot, mild, cold, rain, casual, work, dinner, date night, travel, gym, running, lifting, walking.
- If uncertain, say so briefly in notes instead of inventing details.
`;

const styleProfileInstructions = `
You are FitCheck's private style profile interviewer. Convert a user's plain-language answers
and existing profile fields into an editable wardrobe preference profile.

Rules:
- Keep the profile practical and personal, not generic fashion advice.
- Preserve any strong existing preferences unless the new answers clearly update them.
- Use concise phrases that are useful for outfit recommendation.
- Boldness is 1 for very conservative/classic, 3 for balanced, and 5 for experimental.
- Put hard no's and repeated issues in dislikedCombinations or rules. Preserve concrete rules such as "collared shirts require a belt" or "no shorts for work".
`;

const server = http.createServer(async (request, response) => {
  setCommonHeaders(response);
  const requestURL = new URL(request.url ?? "/", `http://${request.headers.host ?? "localhost"}`);
  const pathname = requestURL.pathname;

  if (request.method === "OPTIONS") {
    response.writeHead(204);
    response.end();
    return;
  }

  if (request.method === "GET" && pathname === "/health") {
    sendJSON(response, 200, {
      ok: true,
      model: openAIModel,
      visionModel: openAIVisionModel,
      imageModel: openAIImageModel,
      imageQuality: openAIImageQuality
    });
    return;
  }

  const supportedPostRoutes = new Set([
    "/outfit-recommendation",
    "/clothing-item-description",
    "/style-profile-draft",
    "/avatar-outfit-preview",
    "/weather-lookup"
  ]);

  if (request.method !== "POST" || !supportedPostRoutes.has(pathname)) {
    sendJSON(response, 404, { error: "Not found" });
    return;
  }

  if (proxyToken && request.headers["x-fitcheck-token"] !== proxyToken) {
    sendJSON(response, 401, { error: "Invalid proxy token" });
    return;
  }

  const isWeatherRoute = pathname === "/weather-lookup";

  if (!isWeatherRoute && !openAIKey) {
    sendJSON(response, 500, { error: "OPENAI_API_KEY is not configured" });
    return;
  }

  try {
    const body = await readJSONBody(request);

    if (isWeatherRoute) {
      const weather = await lookupWeather(body);
      sendJSON(response, 200, weather);
      return;
    }

    if (pathname === "/clothing-item-description") {
      const description = await describeClothingItem(body);
      sendJSON(response, 200, description);
      return;
    }

    if (pathname === "/avatar-outfit-preview") {
      const preview = await generateAvatarOutfitPreview(body);
      sendJSON(response, 200, preview);
      return;
    }

    if (pathname === "/style-profile-draft") {
      const profile = await generateStyleProfile(body);
      sendJSON(response, 200, profile);
      return;
    }

    const review = await reviewOutfit(body);
    sendJSON(response, 200, review);
  } catch (error) {
    sendJSON(response, error.statusCode ?? 500, {
      error: error.message ?? "AI review failed"
    });
  }
});

server.listen(port, host, () => {
  console.log(`FitCheck AI proxy listening on http://${host}:${port}`);
});

async function lookupWeather(requestBody) {
  const date = normalizeWeatherDate(requestBody.date);
  const location = String(requestBody.location ?? "").trim();
  const latitude = Number(requestBody.latitude);
  const longitude = Number(requestBody.longitude);

  if (Number.isFinite(latitude) && Number.isFinite(longitude)) {
    return lookupForecastWithFallback({
      date,
      latitude,
      locationLabel: String(requestBody.locationLabel ?? location ?? "Current Location").trim() || "Current Location",
      longitude
    });
  }

  if (!location) {
    throw httpError(400, "Enter a city or location first.");
  }

  const place = await geocodeWeatherLocation(location);
  return lookupForecastWithFallback({
    date,
    latitude: place.latitude,
    locationLabel: weatherLocationLabel(place),
    longitude: place.longitude
  });
}

async function geocodeWeatherLocation(location) {
  try {
    return await geocodeOpenMeteoLocation(location);
  } catch (openMeteoError) {
    try {
      return await geocodeNominatimLocation(location);
    } catch (nominatimError) {
      throw httpError(
        nominatimError.statusCode ?? openMeteoError.statusCode ?? 502,
        `Location lookup failed. Open-Meteo: ${openMeteoError.message}. Nominatim: ${nominatimError.message}`
      );
    }
  }
}

async function geocodeOpenMeteoLocation(location) {
  const url = new URL("https://geocoding-api.open-meteo.com/v1/search");
  url.searchParams.set("name", location);
  url.searchParams.set("count", "1");
  url.searchParams.set("language", "en");
  url.searchParams.set("format", "json");

  const data = await fetchWeatherJSON(url, "Location lookup failed");
  const result = Array.isArray(data.results) ? data.results[0] : null;

  if (!result || !Number.isFinite(Number(result.latitude)) || !Number.isFinite(Number(result.longitude))) {
    throw httpError(404, "No matching location was found.");
  }

  return {
    latitude: Number(result.latitude),
    longitude: Number(result.longitude),
    name: String(result.name ?? location),
    admin1: result.admin1 ? String(result.admin1) : "",
    country: result.country ? String(result.country) : ""
  };
}

async function geocodeNominatimLocation(location) {
  const url = new URL("https://nominatim.openstreetmap.org/search");
  url.searchParams.set("q", location);
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("limit", "1");
  url.searchParams.set("addressdetails", "1");

  const data = await fetchWeatherJSON(url, "Nominatim location lookup failed", {
    "User-Agent": "FitCheck/1.0 https://github.com/flyboi96/FitCheck"
  });
  const result = Array.isArray(data) ? data[0] : null;

  if (!result || !Number.isFinite(Number(result.lat)) || !Number.isFinite(Number(result.lon))) {
    throw httpError(404, "No matching location was found.");
  }

  const address = result.address && typeof result.address === "object" ? result.address : {};
  const name = String(
    result.name ??
      address.city ??
      address.town ??
      address.village ??
      address.county ??
      location
  );

  return {
    latitude: Number(result.lat),
    longitude: Number(result.lon),
    name,
    admin1: address.state ? String(address.state) : "",
    country: address.country ? String(address.country) : ""
  };
}

async function lookupForecastWithFallback({ date, latitude, locationLabel, longitude }) {
  try {
    return await lookupOpenMeteoForecast({ date, latitude, locationLabel, longitude });
  } catch (openMeteoError) {
    try {
      return await lookupMetNorwayForecast({ date, latitude, locationLabel, longitude });
    } catch (metNorwayError) {
      throw httpError(
        metNorwayError.statusCode ?? openMeteoError.statusCode ?? 502,
        `Weather lookup failed. Open-Meteo: ${openMeteoError.message}. MET Norway: ${metNorwayError.message}`
      );
    }
  }
}

async function lookupOpenMeteoForecast({ date, latitude, locationLabel, longitude }) {
  const url = new URL("https://api.open-meteo.com/v1/forecast");
  url.searchParams.set("latitude", latitude.toString());
  url.searchParams.set("longitude", longitude.toString());
  url.searchParams.set(
    "daily",
    "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,wind_speed_10m_max"
  );
  url.searchParams.set("hourly", "relative_humidity_2m");
  url.searchParams.set("temperature_unit", "fahrenheit");
  url.searchParams.set("wind_speed_unit", "mph");
  url.searchParams.set("precipitation_unit", "inch");
  url.searchParams.set("timezone", "auto");
  url.searchParams.set("start_date", date);
  url.searchParams.set("end_date", date);

  const data = await fetchWeatherJSON(url, "Weather lookup failed");

  const dailyTimes = Array.isArray(data.daily?.time) ? data.daily.time : [];
  const dayIndex = dailyTimes.findIndex((time) => time === date);

  if (dayIndex >= 0) {
    const maxTemperature = Number(data.daily?.temperature_2m_max?.[dayIndex] ?? 75);
    const minTemperature = Number(data.daily?.temperature_2m_min?.[dayIndex] ?? maxTemperature);
    const precipitation = Number(data.daily?.precipitation_sum?.[dayIndex] ?? 0);

    return {
      location: locationLabel,
      temperatureF: Math.round((maxTemperature + minTemperature) / 2),
      highTemperatureF: Math.round(maxTemperature),
      lowTemperatureF: Math.round(minTemperature),
      condition: weatherLookupCodeLabel(data.daily?.weather_code?.[dayIndex]),
      isRaining: precipitation > 0.02,
      humidityPercent: averageWeatherHumidityForDate(data, date),
      windMph: Math.round(Number(data.daily?.wind_speed_10m_max?.[dayIndex] ?? 5)),
      source: "Open-Meteo full-day forecast"
    };
  }

  throw httpError(404, "No forecast was available for that date.");
}

async function lookupMetNorwayForecast({ date, latitude, locationLabel, longitude }) {
  const url = new URL("https://api.met.no/weatherapi/locationforecast/2.0/complete");
  url.searchParams.set("lat", latitude.toFixed(4));
  url.searchParams.set("lon", longitude.toFixed(4));

  const data = await fetchWeatherJSON(url, "MET Norway weather lookup failed", {
    "User-Agent": "FitCheck/1.0 https://github.com/flyboi96/FitCheck"
  });
  const timeseries = Array.isArray(data.properties?.timeseries) ? data.properties.timeseries : [];
  const dayEntries = timeseries.filter((entry) => String(entry.time ?? "").startsWith(date));

  if (dayEntries.length === 0) {
    throw httpError(404, "No MET Norway forecast was available for that date.");
  }

  const temperaturesF = dayEntries
    .map((entry) => celsiusToFahrenheit(entry.data?.instant?.details?.air_temperature))
    .filter((value) => Number.isFinite(value));
  const humidityValues = dayEntries
    .map((entry) => Number(entry.data?.instant?.details?.relative_humidity))
    .filter((value) => Number.isFinite(value));
  const windValuesMph = dayEntries
    .map((entry) => metersPerSecondToMph(entry.data?.instant?.details?.wind_speed))
    .filter((value) => Number.isFinite(value));
  const precipitationMm = dayEntries.reduce(
    (total, entry) => total + metNorwayPrecipitationAmount(entry),
    0
  );
  const symbol = metNorwayRepresentativeSymbol(dayEntries);

  if (temperaturesF.length === 0) {
    throw httpError(404, "MET Norway did not return usable temperature data for that date.");
  }

  return {
    location: locationLabel,
    temperatureF: Math.round(averageNumber(temperaturesF, 75)),
    highTemperatureF: Math.round(Math.max(...temperaturesF)),
    lowTemperatureF: Math.round(Math.min(...temperaturesF)),
    condition: metNorwayConditionLabel(symbol, precipitationMm),
    isRaining: precipitationMm > 0.5,
    humidityPercent: Math.round(averageNumber(humidityValues, 45)),
    windMph: Math.round(Math.max(...windValuesMph, 5)),
    source: "MET Norway forecast"
  };
}

async function fetchWeatherJSON(url, fallbackMessage, headers = {}) {
  let upstreamResponse;

  try {
    upstreamResponse = await fetch(url, {
      headers: {
        Accept: "application/json",
        ...headers
      },
      signal: AbortSignal.timeout(12_000)
    });
  } catch (error) {
    throw httpError(502, `${fallbackMessage}: ${error.message ?? "upstream network request failed"}`);
  }

  const data = await upstreamResponse.json().catch(() => ({}));

  if (!upstreamResponse.ok) {
    throw httpError(502, data.reason || fallbackMessage);
  }

  return data;
}

function averageNumber(values, fallback) {
  if (values.length === 0) {
    return fallback;
  }

  return values.reduce((total, value) => total + value, 0) / values.length;
}

function celsiusToFahrenheit(value) {
  const celsius = Number(value);
  return Number.isFinite(celsius) ? (celsius * 9) / 5 + 32 : NaN;
}

function metersPerSecondToMph(value) {
  const metersPerSecond = Number(value);
  return Number.isFinite(metersPerSecond) ? metersPerSecond * 2.23694 : NaN;
}

function metNorwayPrecipitationAmount(entry) {
  const details =
    entry.data?.next_1_hours?.details ??
    entry.data?.next_6_hours?.details ??
    entry.data?.next_12_hours?.details ??
    {};
  return Number(details.precipitation_amount ?? 0) || 0;
}

function metNorwayRepresentativeSymbol(entries) {
  const noonEntry =
    entries.find((entry) => String(entry.time ?? "").includes("T12:")) ??
    entries[Math.floor(entries.length / 2)] ??
    entries[0];
  return String(
    noonEntry?.data?.next_1_hours?.summary?.symbol_code ??
      noonEntry?.data?.next_6_hours?.summary?.symbol_code ??
      noonEntry?.data?.next_12_hours?.summary?.symbol_code ??
      ""
  );
}

function metNorwayConditionLabel(symbol, precipitationMm) {
  const normalized = symbol.toLowerCase();

  if (normalized.includes("thunder")) {
    return "Storm";
  }

  if (normalized.includes("snow") || normalized.includes("sleet")) {
    return "Snow";
  }

  if (normalized.includes("rain") || precipitationMm > 0.5) {
    return "Rain";
  }

  if (normalized.includes("fog")) {
    return "Fog";
  }

  if (normalized.includes("cloudy")) {
    return "Partly Cloudy";
  }

  if (normalized.includes("fair") || normalized.includes("clearsky")) {
    return "Clear";
  }

  return "Weather";
}

function averageWeatherHumidityForDate(data, date) {
  const hourlyTimes = Array.isArray(data.hourly?.time) ? data.hourly.time : [];
  const humidityValues = hourlyTimes
    .map((time, index) =>
      String(time).startsWith(date) ? Number(data.hourly?.relative_humidity_2m?.[index]) : NaN
    )
    .filter((value) => Number.isFinite(value));

  if (humidityValues.length === 0) {
    return 45;
  }

  return Math.round(humidityValues.reduce((total, value) => total + value, 0) / humidityValues.length);
}

function weatherLocationLabel(place) {
  return [place.name, place.admin1, place.country].filter(Boolean).join(", ");
}

function normalizeWeatherDate(value) {
  const date = String(value ?? "").trim();
  return /^\d{4}-\d{2}-\d{2}$/.test(date) ? date : weatherTodayISO();
}

function weatherTodayISO() {
  return new Date().toISOString().slice(0, 10);
}

function weatherLookupCodeLabel(code) {
  switch (Number(code)) {
    case 0:
      return "Clear";
    case 1:
    case 2:
    case 3:
      return "Partly Cloudy";
    case 45:
    case 48:
      return "Fog";
    case 51:
    case 53:
    case 55:
    case 56:
    case 57:
      return "Drizzle";
    case 61:
    case 63:
    case 65:
    case 66:
    case 67:
      return "Rain";
    case 71:
    case 73:
    case 75:
    case 77:
      return "Snow";
    case 80:
    case 81:
    case 82:
      return "Rain Showers";
    case 85:
    case 86:
      return "Snow Showers";
    case 95:
    case 96:
    case 99:
      return "Storm";
    default:
      return "Weather";
  }
}

async function reviewOutfit(requestBody) {
  const closet = Array.isArray(requestBody.closet) ? requestBody.closet : [];
  if (closet.length === 0) {
    throw httpError(400, "closet is required");
  }

  const knownIDs = new Set(closet.map((item) => item.id).filter(Boolean));
  const candidateItemIDs = Array.isArray(requestBody.candidateItemIDs)
    ? requestBody.candidateItemIDs.filter((id) => knownIDs.has(id))
    : [];

  const promptPayload = {
    context: requestBody.context ?? "",
    contextLabel: requestBody.contextLabel ?? requestBody.occasion ?? "",
    contextDefinition: requestBody.contextDefinition ?? "",
    weatherSummary: requestBody.weatherSummary ?? "",
    occasion: requestBody.occasion ?? "",
    activity: requestBody.activity ?? "",
    styleDescription: requestBody.styleDescription ?? "",
    selectedItemID: requestBody.selectedItemID ?? null,
    candidateItemIDs,
    localScore: requestBody.localScore ?? null,
    localNotes: Array.isArray(requestBody.localNotes) ? requestBody.localNotes : [],
    recentFeedback: Array.isArray(requestBody.recentFeedback) ? requestBody.recentFeedback : [],
    closet: closet.map((item) => ({
      id: item.id,
      name: item.name,
      brand: item.brand,
      category: item.category,
      color: item.color,
      material: item.material,
      quantity: item.quantity,
      pattern: item.pattern,
      formalityLevel: item.formalityLevel,
      weatherSuitability: item.weatherSuitability,
      occasionSuitability: item.occasionSuitability,
      activitySuitability: item.activitySuitability,
      notes: item.notes
    }))
  };

  const openAIResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${openAIKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: openAIModel,
      instructions,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: JSON.stringify(promptPayload)
            }
          ]
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: "fitcheck_outfit_review",
          strict: true,
          schema: responseSchema
        }
      },
      max_output_tokens: 2000,
      store: false
    })
  });


  const data = await openAIResponse.json().catch(() => ({}));
  if (!openAIResponse.ok) {
    throw httpError(openAIResponse.status, data.error?.message ?? "OpenAI request failed");
  }

  const parsed = parseOpenAIJSON(data, "OpenAI outfit review");
  const itemIDs = Array.isArray(parsed.itemIDs)
    ? parsed.itemIDs.filter((id) => knownIDs.has(id))
    : [];

  return {
    itemIDs: itemIDs.length > 0 ? itemIDs : candidateItemIDs,
    rationale: String(parsed.rationale ?? "AI review completed."),
    cautions: Array.isArray(parsed.cautions) ? parsed.cautions.map(String).slice(0, 5) : []
  };
}

async function describeClothingItem(requestBody) {
  const imageBase64 = String(requestBody.imageBase64 ?? "").trim();

  if (!imageBase64) {
    throw httpError(400, "imageBase64 is required");
  }

  if (!/^[A-Za-z0-9+/=]+$/.test(imageBase64)) {
    throw httpError(400, "imageBase64 must be a base64-encoded image");
  }

  const requestedMimeType = String(requestBody.mimeType ?? "image/jpeg").toLowerCase();
  const mimeType = ["image/jpeg", "image/png", "image/webp", "image/gif"].includes(requestedMimeType)
    ? requestedMimeType
    : "image/jpeg";
  const dataURL = `data:${mimeType};base64,${imageBase64}`;
  const userDescription = String(requestBody.userDescription ?? "").trim();

  const promptPayload = {
    userDescription,
    wearerProfile: requestBody.wearerProfile ?? "",
    allowedCategories: clothingCategories
  };

  const openAIResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${openAIKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: openAIVisionModel,
      instructions: clothingDescriptionInstructions,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: JSON.stringify(promptPayload)
            },
            {
              type: "input_image",
              image_url: dataURL
            }
          ]
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: "fitcheck_clothing_description",
          strict: true,
          schema: clothingDescriptionSchema
        }
      },
      max_output_tokens: 1200,
      store: false
    })
  });

  const data = await openAIResponse.json().catch(() => ({}));
  if (!openAIResponse.ok) {
    throw httpError(openAIResponse.status, data.error?.message ?? "OpenAI request failed");
  }

  const parsed = parseOpenAIJSON(data, "OpenAI clothing import");
  const category = clothingCategories.includes(parsed.category) ? parsed.category : "other";

  return {
    name: String(parsed.name ?? "").trim(),
    category,
    color: String(parsed.color ?? "").trim(),
    material: String(parsed.material ?? "").trim(),
    pattern: String(parsed.pattern ?? "").trim(),
    formalityLevel: clampInteger(parsed.formalityLevel, 1, 5, 3),
    weatherSuitability: String(parsed.weatherSuitability ?? "").trim(),
    occasionSuitability: String(parsed.occasionSuitability ?? "").trim(),
    activitySuitability: String(parsed.activitySuitability ?? "").trim(),
    notes: String(parsed.notes ?? "").trim()
  };
}

async function generateStyleProfile(requestBody) {
  const questionnaireAnswers = String(requestBody.questionnaireAnswers ?? "").trim();
  if (!questionnaireAnswers) {
    throw httpError(400, "questionnaireAnswers is required");
  }

  const promptPayload = {
    wearerProfile: requestBody.wearerProfile ?? "",
    currentProfile: {
      styleDescription: requestBody.currentStyleDescription ?? "",
      favoriteLooks: requestBody.currentFavoriteLooks ?? "",
      preferredColors: requestBody.currentPreferredColors ?? "",
      preferredFit: requestBody.currentPreferredFit ?? "",
      dislikedCombinations: requestBody.currentDislikedCombinations ?? "",
      rules: requestBody.currentRules ?? "",
      boldness: requestBody.currentBoldness ?? 3
    },
    questionnaireAnswers
  };

  const openAIResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${openAIKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: openAIModel,
      instructions: styleProfileInstructions,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: JSON.stringify(promptPayload)
            }
          ]
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: "fitcheck_style_profile",
          strict: true,
          schema: styleProfileSchema
        }
      },
      max_output_tokens: 3000,
      store: false
    })
  });

  const data = await openAIResponse.json().catch(() => ({}));
  if (!openAIResponse.ok) {
    throw httpError(openAIResponse.status, data.error?.message ?? "OpenAI request failed");
  }

  const parsed = parseOpenAIJSON(data, "OpenAI style profile");
  return {
    styleDescription: String(parsed.styleDescription ?? "").trim(),
    favoriteLooks: String(parsed.favoriteLooks ?? "").trim(),
    preferredColors: String(parsed.preferredColors ?? "").trim(),
    preferredFit: String(parsed.preferredFit ?? "").trim(),
    dislikedCombinations: String(parsed.dislikedCombinations ?? "").trim(),
    rules: String(parsed.rules ?? "").trim(),
    boldness: clampInteger(parsed.boldness, 1, 5, 3)
  };
}

async function generateAvatarOutfitPreview(requestBody) {
  const imageBase64 = String(requestBody.userImageBase64 ?? "").trim();

  if (!imageBase64) {
    throw httpError(400, "userImageBase64 is required");
  }

  if (!/^[A-Za-z0-9+/=]+$/.test(imageBase64)) {
    throw httpError(400, "userImageBase64 must be a base64-encoded image");
  }

  const requestedMimeType = String(requestBody.mimeType ?? "image/jpeg").toLowerCase();
  const mimeType = ["image/jpeg", "image/png", "image/webp"].includes(requestedMimeType)
    ? requestedMimeType
    : "image/jpeg";
  const imageBuffer = Buffer.from(imageBase64, "base64");
  const outfitItems = Array.isArray(requestBody.outfitItems) ? requestBody.outfitItems : [];
  const promptSummary = outfitItems.length > 0
    ? `Avatar outfit preview with ${outfitItems.map((item) => item.name).join(", ")}`
    : "Base realistic FitCheck avatar";

  const prompt = buildAvatarPrompt({
    outfitItems,
    weatherSummary: requestBody.weatherSummary ?? "",
    location: requestBody.location ?? "",
    backgroundContext: requestBody.backgroundContext ?? "",
    wearerProfile: requestBody.wearerProfile ?? "",
    styleDescription: requestBody.styleDescription ?? "",
    avatarNotes: requestBody.avatarNotes ?? "",
    weatherCondition: requestBody.weatherCondition ?? "",
    temperatureF: requestBody.temperatureF,
    isRaining: requestBody.isRaining,
    windMph: requestBody.windMph,
    humidityPercent: requestBody.humidityPercent,
    usesSavedAvatar: Boolean(requestBody.usesSavedAvatar)
  });

  const formData = new FormData();
  formData.set("model", openAIImageModel);
  formData.set("prompt", prompt);
  formData.set("size", "1024x1536");
  formData.set("quality", openAIImageQuality);
  formData.set("background", "opaque");
  formData.set("output_format", "png");
  formData.append("image", new Blob([imageBuffer], { type: mimeType }), `fitcheck-avatar-reference.${fileExtension(mimeType)}`);

  const openAIResponse = await fetch("https://api.openai.com/v1/images/edits", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${openAIKey}`
    },
    body: formData
  });

  const data = await openAIResponse.json().catch(() => ({}));
  if (!openAIResponse.ok) {
    throw httpError(openAIResponse.status, data.error?.message ?? "OpenAI image request failed");
  }

  const imageData = data.data?.[0]?.b64_json;
  if (typeof imageData !== "string" || !imageData.trim()) {
    console.error("OpenAI image response without b64_json:", JSON.stringify(data, null, 2));
    throw new Error("OpenAI image response did not include image data");
  }

  return {
    imageBase64: imageData,
    mimeType: "image/png",
    promptSummary
  };
}

function buildAvatarPrompt({
  outfitItems,
  weatherSummary,
  location,
  backgroundContext,
  wearerProfile,
  styleDescription,
  avatarNotes,
  weatherCondition,
  temperatureF,
  isRaining,
  windMph,
  humidityPercent,
  usesSavedAvatar
}) {
  const outfitDescription = outfitItems.length > 0
    ? outfitItems
        .map((item) => {
          const details = [
            item.name,
            item.category,
            item.color,
            item.pattern,
            item.notes
          ]
            .map((value) => String(value ?? "").trim())
            .filter(Boolean)
            .join(", ");
          return `- ${details}`;
        })
        .join("\n")
    : "- Plain dark t-shirt, neutral pants, and simple shoes for avatar setup only. Keep the clothing simple and understated.";
  const temperature = Number(temperatureF);
  const wind = Number(windMph);
  const humidity = Number(humidityPercent);
  const hasTemperature = Number.isFinite(temperature);
  const hasWind = Number.isFinite(wind);
  const hasHumidity = Number.isFinite(humidity);
  const rainingText = typeof isRaining === "boolean" ? (isRaining ? "yes" : "no") : "unknown";
  const weatherRules = weatherVisualRules({
    location,
    weatherCondition,
    temperatureF: hasTemperature ? temperature : null,
    isRaining,
    humidityPercent: hasHumidity ? humidity : null
  });
  const referenceMode = usesSavedAvatar
    ? "The input image is the user's saved FitCheck avatar. Preserve the avatar's face, hair or hat, body proportions, posture, and full head-to-shoes framing; change only the clothing and setting needed for this outfit preview."
    : "The input image is a user reference photo. Create a reusable, realistic full-body FitCheck avatar while preserving broad facial features, hairstyle or hat impression, skin tone, body proportions, and pose realism.";

  return `
Edit the provided user photo into a realistic, full-body FitCheck avatar preview.

Goal:
- ${referenceMode}
- Show the outfit clearly from head to toe as a practical wardrobe try-on preview.
- Use a natural, realistic background informed by location and weather.
- Keep the result private-app appropriate: no text labels, no logos unless they are visible on the listed clothing, no identity documents, no dramatic fashion editorial styling.

Composition requirements:
- Vertical full-body standing portrait, camera pulled back far enough to show the complete person from the top of hair or hat through the soles of both shoes.
- The person must occupy about 70-85% of image height, leaving visible margin above the hair/hat and below the shoes.
- Include the complete neck, shoulders, arms/hands, legs, ankles, shoes, and feet.
- No cropped hair, no cropped hat, no cropped neck, no cropped shoes, no below-knee crop, no waist-up portrait, no close-up framing, and no feet hidden by the image edge.
- If the reference photo is cropped, conservatively complete the missing head, hair/hat, neck, lower legs, or shoes so the final preview is still head-to-toe.
- If necessary, zoom the camera out and use a simpler background instead of cropping the person.

Outfit to visualize:
${outfitDescription}

Wearer profile: ${String(wearerProfile ?? "").trim() || "unspecified"}
Style preferences:
${String(styleDescription ?? "").trim() || "No saved style notes."}

Avatar notes:
${String(avatarNotes ?? "").trim() || "No avatar-specific notes."}

Weather and setting:
- Location: ${String(location ?? "").trim() || "unspecified"}
- Weather: ${String(weatherSummary ?? "").trim() || "unspecified"}
- Condition: ${String(weatherCondition ?? "").trim() || "unspecified"}
- Temperature: ${hasTemperature ? `${Math.round(temperature)}F` : "unspecified"}
- Is raining: ${rainingText}
- Wind: ${hasWind ? `${Math.round(wind)} mph` : "unspecified"}
- Humidity: ${hasHumidity ? `${Math.round(humidity)}%` : "unspecified"}
- Background guidance: ${String(backgroundContext ?? "").trim() || "Use a subtle outdoor or indoor setting that matches the weather and does not distract from the outfit."}
- Weather visual rules: ${weatherRules}

Rendering instructions:
- Realistic smartphone-photo look.
- The clothing should match the closet item descriptions as closely as possible.
- If a detail is unknown, make a conservative, ordinary choice instead of adding bold new clothing.
- Do not duplicate clothing items or add extra accessories unless the outfit list includes them.
- Do not substitute a generic gray rainy Pacific Northwest city unless the location and weather actually call for that.
`.trim();
}

function weatherVisualRules({ location, weatherCondition, temperatureF, isRaining, humidityPercent }) {
  const normalizedLocation = String(location ?? "").toLowerCase();
  const normalizedCondition = String(weatherCondition ?? "").toLowerCase();
  const rules = [];

  if (isRaining === false && !normalizedCondition.includes("rain") && !normalizedCondition.includes("storm")) {
    rules.push("No rain, no wet pavement, no umbrellas, no mist, no storm clouds, and no heavy gray overcast.");
  } else if (isRaining === true || normalizedCondition.includes("rain") || normalizedCondition.includes("storm")) {
    rules.push("Show the actual wet-weather context, but keep the outfit visible and not hidden by rain gear unless listed.");
  }

  if (typeof temperatureF === "number" && temperatureF >= 90) {
    rules.push("Make the scene visibly hot: bright sun, dry light, heat-appropriate atmosphere, and no cold-weather mood.");
  } else if (typeof temperatureF === "number" && temperatureF >= 80) {
    rules.push("Make the scene warm and sunlit unless the condition explicitly says otherwise.");
  } else if (typeof temperatureF === "number" && temperatureF <= 45) {
    rules.push("Make the scene cool or cold, but do not obscure the outfit.");
  }

  if (typeof humidityPercent === "number" && humidityPercent >= 70 && typeof temperatureF === "number" && temperatureF >= 75) {
    rules.push("Use humid warm-weather cues without making the scene rainy unless rain is explicitly reported.");
  }

  if (normalizedCondition.includes("clear")) {
    rules.push("Use clear sky or strong sunlight cues.");
  }

  if (normalizedLocation.includes("djibouti")) {
    rules.push("For Djibouti, use hot, bright, dry, arid/coastal Horn of Africa visual cues; avoid Seattle-like gray rain unless rain is explicitly reported.");
  }

  return rules.join(" ") || "Match the named location and weather literally, using conservative realistic visual cues.";
}

function fileExtension(mimeType) {
  switch (mimeType) {
    case "image/png":
      return "png";
    case "image/webp":
      return "webp";
    default:
      return "jpg";
  }
}

function extractOpenAIText(data) {
  if (typeof data.output_text === "string" && data.output_text.trim()) {
    return data.output_text.trim();
  }

  const textParts = [];

  for (const output of data.output ?? []) {
    for (const content of output.content ?? []) {
      if (typeof content.text === "string") {
        textParts.push(content.text);
      }

      if (typeof content.value === "string") {
        textParts.push(content.value);
      }
    }
  }

  for (const choice of data.choices ?? []) {
    const choiceText = choice?.message?.content ?? choice?.text;
    if (typeof choiceText === "string") {
      textParts.push(choiceText);
    }
  }

  return textParts.join("\n").trim();
}

function parseOpenAIJSON(data, contextLabel) {
  const outputText = extractOpenAIText(data);

  if (data.status === "incomplete") {
    const reason = data.incomplete_details?.reason ?? "unknown reason";
    throw new Error(`${contextLabel} response was cut off before it finished (${reason}). Try again, or shorten the answers.`);
  }

  if (!outputText) {
    console.error(`${contextLabel} response without extractable text:`, JSON.stringify(data, null, 2));

    const refusal = extractOpenAIRefusal(data);
    if (refusal) {
      throw new Error(`OpenAI refused the request: ${refusal}`);
    }

    throw new Error(`${contextLabel} did not include output text`);
  }

  try {
    return JSON.parse(outputText);
  } catch (error) {
    console.error(`${contextLabel} returned invalid JSON:`, outputText.slice(0, 2000));
    throw new Error(`${contextLabel} returned incomplete JSON. Try again; if it repeats, shorten the answers or use a model with a larger output limit.`);
  }
}

function extractOpenAIRefusal(data) {
  for (const output of data.output ?? []) {
    for (const content of output.content ?? []) {
      if (typeof content.refusal === "string" && content.refusal.trim()) {
        return content.refusal.trim();
      }
    }
  }

  return "";
}

function readJSONBody(request) {
  return new Promise((resolve, reject) => {
    let body = "";

    request.on("data", (chunk) => {
      body += chunk;
      if (Buffer.byteLength(body) > maxBodyBytes) {
        reject(httpError(413, "Request body is too large"));
        request.destroy();
      }
    });

    request.on("end", () => {
      try {
        resolve(JSON.parse(body || "{}"));
      } catch {
        reject(httpError(400, "Request body must be valid JSON"));
      }
    });

    request.on("error", reject);
  });
}

function setCommonHeaders(response) {
  response.setHeader("Access-Control-Allow-Origin", "*");
  response.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  response.setHeader("Access-Control-Allow-Headers", "Content-Type,X-FitCheck-Token");
}

function sendJSON(response, statusCode, payload) {
  response.writeHead(statusCode, { "Content-Type": "application/json" });
  response.end(JSON.stringify(payload));
}

function httpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function clampInteger(value, minimum, maximum, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return fallback;
  }
  return Math.min(maximum, Math.max(minimum, Math.round(number)));
}
