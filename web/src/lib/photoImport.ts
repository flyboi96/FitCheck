import {
  clothingCategories,
  defaultClothingItemDraft,
  type ClothingCategory,
  type ClothingItemDraft,
} from './closet'
import { compactEncodedImageForFirestore, imageFileToBase64 } from './images'
import type { WearerProfile } from './profile'
import { getAIProxySettings } from './settings'

type ClothingDescriptionResponse = {
  name?: string
  category?: string
  color?: string
  material?: string
  pattern?: string
  weatherSuitability?: string
  occasionSuitability?: string
  activitySuitability?: string
  notes?: string
  imageBase64?: string
  imageMimeType?: string
  imagePromptSummary?: string
}

export type CleanClothingItemPhotoResult = {
  imageBase64: string
  imageMimeType: string
  imagePromptSummary: string
}

export async function describeClothingPhoto({
  file,
  userDescription,
  wearerProfile,
}: {
  file: File
  userDescription: string
  wearerProfile: WearerProfile
}): Promise<ClothingItemDraft> {
  const data = await requestClothingDescription({
    file,
    userDescription,
    wearerProfile,
  })

  const tags = [
    data.weatherSuitability ? `Weather: ${data.weatherSuitability}` : null,
    data.occasionSuitability ? `Occasion: ${data.occasionSuitability}` : null,
    data.activitySuitability ? `Activity: ${data.activitySuitability}` : null,
    data.imagePromptSummary ? `Image: ${data.imagePromptSummary}` : null,
    data.notes,
  ].filter(Boolean)
  const cleanedImage = await compactImportedClothingImage(data)

  return {
    ...defaultClothingItemDraft,
    name: data.name?.trim() || '',
    category: categoryValue(data.category),
    color: data.color?.trim() || '',
    material: data.material?.trim() || '',
    pattern: data.pattern?.trim() || '',
    imageBase64: cleanedImage?.base64 ?? '',
    imageMimeType: cleanedImage?.mimeType ?? '',
    notes: tags.join('\n'),
  }
}

export async function cleanClothingPhotoForItem({
  file,
  item,
  wearerProfile,
}: {
  file: File
  item: ClothingItemDraft
  wearerProfile: WearerProfile
}): Promise<CleanClothingItemPhotoResult> {
  const data = await requestClothingDescription({
    file,
    userDescription: existingItemDescription(item),
    wearerProfile,
    targetItem: item,
  })
  const cleanedImage = await compactImportedClothingImage(data)

  if (!cleanedImage) {
    throw new Error('AI described the item but did not return a cleaned clothing image.')
  }

  return {
    imageBase64: cleanedImage.base64,
    imageMimeType: cleanedImage.mimeType,
    imagePromptSummary: data.imagePromptSummary?.trim() || `Clean closet image generated for ${item.name}.`,
  }
}

async function requestClothingDescription({
  file,
  targetItem,
  userDescription,
  wearerProfile,
}: {
  file: File
  targetItem?: ClothingItemDraft
  userDescription: string
  wearerProfile: WearerProfile
}) {
  const settings = getAIProxySettings()
  const baseURL = settings.proxyUrl.trim().replace(/\/+$/, '')

  if (!baseURL) {
    throw new Error('AI proxy URL is not configured in More.')
  }

  const image = await imageFileToBase64(file)
  const response = await fetch(`${baseURL}/clothing-item-description`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(settings.proxyToken.trim() ? { 'X-FitCheck-Token': settings.proxyToken.trim() } : {}),
    },
    body: JSON.stringify({
      imageBase64: image.base64,
      mimeType: image.mimeType,
      targetItem: targetItem
        ? {
            name: targetItem.name,
            brand: targetItem.brand,
            category: targetItem.category,
            color: targetItem.color,
            material: targetItem.material,
            pattern: targetItem.pattern,
          }
        : null,
      userDescription,
      wearerProfile,
    }),
  })
  const data = (await response.json().catch(() => ({}))) as ClothingDescriptionResponse & {
    error?: string
  }

  if (!response.ok) {
    throw new Error(data.error || 'AI clothing photo import failed.')
  }

  return data
}

async function compactImportedClothingImage(data: ClothingDescriptionResponse) {
  if (!data.imageBase64) {
    return null
  }

  try {
    return await compactEncodedImageForFirestore(
      {
        base64: data.imageBase64,
        mimeType: data.imageMimeType || 'image/png',
      },
      {
        maxBase64Length: 650_000,
        maxDimension: 720,
        minDimension: 360,
        quality: 0.74,
      },
    )
  } catch {
    return null
  }
}

function categoryValue(value: unknown): ClothingCategory {
  return typeof value === 'string' &&
    clothingCategories.some((category) => category.value === value)
    ? (value as ClothingCategory)
    : 'other'
}

function existingItemDescription(item: ClothingItemDraft) {
  return [
    'Clean this photo for an existing FitCheck closet item.',
    `Target item: ${item.name || 'unnamed clothing item'}.`,
    item.brand ? `Brand: ${item.brand}.` : '',
    `Category: ${item.category}.`,
    item.color ? `Color: ${item.color}.` : '',
    item.material ? `Material: ${item.material}.` : '',
    item.pattern ? `Pattern: ${item.pattern}.` : '',
    item.notes ? `Saved notes: ${item.notes}.` : '',
    'If a person is wearing the item, isolate only the target clothing item and remove the person plus other garments.',
  ]
    .filter(Boolean)
    .join(' ')
}
