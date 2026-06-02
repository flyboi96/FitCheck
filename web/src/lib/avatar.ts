import { type ClothingItem } from './closet'
import { imageFileToBase64 } from './images'
import { weatherSummary, type OutfitRecommendation, type WeatherInput } from './outfits'
import type { UserProfile } from './profile'
import { getAIProxySettings } from './settings'

type AvatarPreviewResponse = {
  imageBase64?: string
  mimeType?: string
  promptSummary?: string
  error?: string
}

export type AvatarPreview = {
  imageURL: string
  promptSummary: string
}

export async function generateAvatarPreview({
  file,
  profile,
  recommendation,
  weather,
}: {
  file: File
  profile: UserProfile | null
  recommendation: OutfitRecommendation
  weather: WeatherInput
}): Promise<AvatarPreview> {
  const settings = getAIProxySettings()
  const baseURL = settings.proxyUrl.trim().replace(/\/+$/, '')

  if (!baseURL) {
    throw new Error('AI proxy URL is not configured in More.')
  }

  const image = await imageFileToBase64(file, 1600, 0.88)
  const response = await fetch(`${baseURL}/avatar-outfit-preview`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(settings.proxyToken.trim() ? { 'X-FitCheck-Token': settings.proxyToken.trim() } : {}),
    },
    body: JSON.stringify({
      userImageBase64: image.base64,
      mimeType: image.mimeType,
      outfitItems: recommendation.items.map(itemPayload),
      weatherSummary: weatherSummary(weather),
      location: weather.location,
      backgroundContext: weather.condition,
      wearerProfile: profile?.gender ?? '',
      styleDescription: profile?.styleDescription ?? '',
      avatarNotes: 'Full-body realistic avatar preview. Include hair/head and shoes.',
      weatherCondition: weather.condition,
      temperatureF: weather.temperatureF,
      isRaining: weather.isRaining,
      windMph: weather.windMph,
      humidityPercent: weather.humidityPercent,
      usesSavedAvatar: false,
    }),
  })
  const data = (await response.json().catch(() => ({}))) as AvatarPreviewResponse

  if (!response.ok) {
    throw new Error(data.error || 'Avatar preview failed.')
  }

  if (!data.imageBase64) {
    throw new Error('Avatar response did not include an image.')
  }

  const mimeType = data.mimeType || 'image/png'
  return {
    imageURL: `data:${mimeType};base64,${data.imageBase64}`,
    promptSummary: data.promptSummary || 'Avatar preview generated.',
  }
}

function itemPayload(item: ClothingItem) {
  return {
    id: item.id,
    name: item.name,
    brand: item.brand,
    category: item.category,
    quantity: item.quantity,
    color: item.color,
    pattern: item.pattern,
    formalityLevel: 3,
    weatherSuitability: '',
    occasionSuitability: '',
    activitySuitability: '',
    notes: item.notes,
  }
}
