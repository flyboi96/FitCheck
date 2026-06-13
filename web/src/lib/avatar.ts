import {
  deleteDoc,
  doc,
  onSnapshot,
  serverTimestamp,
  setDoc,
  type FirestoreError,
  type Unsubscribe,
} from 'firebase/firestore'
import { type ClothingItem } from './closet'
import { db } from './firebase'
import { compactEncodedImageForFirestore, imageFileToBase64 } from './images'
import { weatherSummary, type OutfitRecommendation, type WeatherInput } from './outfits'
import { profileStyleSummary, type UserProfile } from './profile'
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
  imageBase64: string
  mimeType: string
}

export async function generateAvatarPreview({
  file,
  profile,
  recommendation,
  savedAvatar,
  weather,
}: {
  file?: File | null
  profile: UserProfile | null
  recommendation: OutfitRecommendation
  savedAvatar?: SavedAvatar | null
  weather: WeatherInput
}): Promise<AvatarPreview> {
  const settings = getAIProxySettings()
  const baseURL = settings.proxyUrl.trim().replace(/\/+$/, '')

  if (!baseURL) {
    throw new Error('AI proxy URL is not configured in More.')
  }

  const image = savedAvatar
    ? { base64: savedAvatar.imageBase64, mimeType: savedAvatar.mimeType }
    : file
      ? await imageFileToBase64(file, 1600, 0.88)
      : null

  if (!image) {
    throw new Error('Choose a full-body reference photo or save an avatar first.')
  }

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
      styleDescription: profileStyleSummary(profile),
      avatarNotes: 'Full-body realistic avatar preview. Include hair/head and shoes.',
      weatherCondition: weather.condition,
      temperatureF: weather.temperatureF,
      highTemperatureF: weather.highTemperatureF,
      lowTemperatureF: weather.lowTemperatureF,
      isRaining: weather.isRaining,
      windMph: weather.windMph,
      humidityPercent: weather.humidityPercent,
      usesSavedAvatar: Boolean(savedAvatar),
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
    imageBase64: data.imageBase64,
    mimeType,
  }
}

export type SavedAvatar = {
  id: string
  imageBase64: string
  mimeType: string
  imageURL: string
  notes: string
  updatedAt: string
}

function requireFirestore() {
  if (!db) {
    throw new Error('Firebase is not configured.')
  }

  return db
}

function savedAvatarDoc(userId: string) {
  return doc(requireFirestore(), 'users', userId, 'avatars', 'default')
}

export function subscribeToSavedAvatar(
  userId: string,
  onAvatar: (avatar: SavedAvatar | null) => void,
  onError: (error: FirestoreError) => void,
): Unsubscribe {
  return onSnapshot(
    savedAvatarDoc(userId),
    (snapshot) => {
      onAvatar(snapshot.exists() ? normalizeSavedAvatar(snapshot.id, snapshot.data()) : null)
    },
    onError,
  )
}

export async function saveGeneratedAvatar({
  avatar,
  notes,
  userId,
}: {
  avatar: Pick<SavedAvatar, 'imageBase64' | 'mimeType'>
  notes: string
  userId: string
}) {
  const compactAvatar = await compactEncodedImageForFirestore({
    base64: avatar.imageBase64,
    mimeType: avatar.mimeType,
  })

  await setDoc(
    savedAvatarDoc(userId),
    {
      imageBase64: compactAvatar.base64,
      mimeType: compactAvatar.mimeType,
      notes: notes.trim(),
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  )
}

export async function saveReferenceAvatar({
  file,
  notes,
  userId,
}: {
  file: File
  notes: string
  userId: string
}) {
  const image = await imageFileToBase64(file, 1200, 0.82)
  await saveGeneratedAvatar({
    avatar: {
      imageBase64: image.base64,
      mimeType: image.mimeType,
    },
    notes,
    userId,
  })
}

export async function deleteSavedAvatar(userId: string) {
  await deleteDoc(savedAvatarDoc(userId))
}

function normalizeSavedAvatar(id: string, data: Record<string, unknown>): SavedAvatar {
  const mimeType = typeof data.mimeType === 'string' ? data.mimeType : 'image/png'
  const imageBase64 = typeof data.imageBase64 === 'string' ? data.imageBase64 : ''
  const updatedAt = data.updatedAt as { toDate?: () => Date } | undefined

  return {
    id,
    imageBase64,
    mimeType,
    imageURL: `data:${mimeType};base64,${imageBase64}`,
    notes: typeof data.notes === 'string' ? data.notes : '',
    updatedAt: updatedAt?.toDate?.().toISOString() ?? '',
  }
}

export async function generateBaseAvatar({
  file,
  notes,
  profile,
}: {
  file: File
  notes: string
  profile: UserProfile | null
}) {
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
      outfitItems: [],
      weatherSummary: 'Neutral indoor lighting for saved FitCheck avatar setup.',
      location: '',
      backgroundContext: 'neutral studio',
      wearerProfile: profile?.gender ?? '',
      styleDescription: profileStyleSummary(profile),
      avatarNotes: [
        'Create a reusable realistic full-body avatar for future outfit previews.',
        'Show head, hair or hat, hands, legs, and shoes with no cropping.',
        notes.trim(),
      ]
        .filter(Boolean)
        .join(' '),
      weatherCondition: '',
      temperatureF: 72,
      isRaining: false,
      windMph: 0,
      humidityPercent: 45,
      usesSavedAvatar: false,
    }),
  })
  const data = (await response.json().catch(() => ({}))) as AvatarPreviewResponse

  if (!response.ok) {
    throw new Error(data.error || 'Base avatar generation failed.')
  }

  if (!data.imageBase64) {
    throw new Error('Avatar response did not include an image.')
  }

  const mimeType = data.mimeType || 'image/png'
  return {
    imageURL: `data:${mimeType};base64,${data.imageBase64}`,
    promptSummary: data.promptSummary || 'Base avatar generated.',
    imageBase64: data.imageBase64,
    mimeType,
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
    material: item.material,
    pattern: item.pattern,
    imageBase64: item.imageBase64,
    imageMimeType: item.imageMimeType,
    formalityLevel: 3,
    weatherSuitability: '',
    occasionSuitability: '',
    activitySuitability: '',
    notes: item.notes,
  }
}
