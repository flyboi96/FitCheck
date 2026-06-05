import { addDoc, collection, getDocs, serverTimestamp } from 'firebase/firestore'
import { db } from './firebase'
import {
  categoryLabel,
  type ClothingCategory,
  type ClothingItem,
} from './closet'
import { contextOptionsFromSettings, contextStylesPrompt, loadContextStyles } from './contextStyles'
import {
  defaultContextDescription,
  defaultContextLabel,
  outfitContexts,
  type OutfitContext,
  type OutfitContextOption,
} from './outfitContextCatalog'
import { profileStyleSummary, type UserProfile } from './profile'
import { getAIProxySettings } from './settings'

export {
  isDefaultOutfitContext,
  normalizeOutfitContext,
  outfitContexts,
  type OutfitContext,
  type OutfitContextOption,
} from './outfitContextCatalog'
export type OutfitSource = 'ai' | 'local'
export type OutfitFeedbackType = 'liked' | 'rejected' | 'issue'

export type WeatherInput = {
  location: string
  temperatureF: number
  condition: string
  isRaining: boolean
  humidityPercent: number
  windMph: number
}

export type OutfitRecommendation = {
  id: string
  items: ClothingItem[]
  score: number
  scoreLabel: string
  source: OutfitSource
  rationale: string
  reasons: string[]
  cautions: string[]
}

export type OutfitGenerationRequest = {
  closet: ClothingItem[]
  context: OutfitContext
  weather: WeatherInput
  profile: UserProfile | null
  userId: string
  selectedItemId?: string
  askAIFirst: boolean
}

type ItemRole = 'top' | 'bottom' | 'fullBody' | 'shoes' | 'outerwear' | 'belt' | 'socks' | 'accessory'

function contextDetails(context: OutfitContext, options: OutfitContextOption[] = outfitContexts) {
  return (
    options.find((option) => option.value === context) ?? {
      value: context,
      label: defaultContextLabel(context),
      description: defaultContextDescription(context),
    }
  )
}

function isExerciseContext(context: OutfitContext) {
  const contextText = normalizedContextText(context)
  return /lifting|running|gym|training|workout|strength|run/.test(contextText)
}

function isRunningContext(context: OutfitContext) {
  return /running|run|jog/.test(normalizedContextText(context))
}

function isLiftingContext(context: OutfitContext) {
  return /lifting|lift|strength|gym|training/.test(normalizedContextText(context))
}

function isWorkContext(context: OutfitContext) {
  return /work|office|business|pilot|meeting|briefing|tdy/.test(normalizedContextText(context))
}

function normalizedContextText(context: OutfitContext) {
  return context.toLowerCase().replace(/[^a-z]/g, '')
}

export const defaultWeatherInput: WeatherInput = {
  location: '',
  temperatureF: 75,
  condition: 'Clear',
  isRaining: false,
  humidityPercent: 45,
  windMph: 5,
}

export async function generateOutfit(
  request: OutfitGenerationRequest,
): Promise<OutfitRecommendation> {
  const localRecommendation = generateLocalOutfit(request)

  if (!request.askAIFirst) {
    return localRecommendation
  }

  try {
    const aiRecommendation = await requestAIOutfit(request)
    return aiRecommendation.items.length > 0 ? aiRecommendation : localRecommendation
  } catch (error) {
    return {
      ...localRecommendation,
      rationale: 'AI was unavailable, so FitCheck used the local closet scorer.',
      cautions: [
        error instanceof Error ? error.message : 'AI proxy request failed.',
        ...localRecommendation.cautions,
      ].slice(0, 5),
    }
  }
}

export function generateLocalOutfit({
  closet,
  context,
  profile,
  selectedItemId,
  weather,
}: OutfitGenerationRequest): OutfitRecommendation {
  const availableItems = closet.filter((item) => item.status === 'active')
  const selectedItem = availableItems.find((item) => item.id === selectedItemId)
  const selectedRole = selectedItem ? itemRole(selectedItem) : null
  const items: ClothingItem[] = []

  function addItem(item: ClothingItem | null | undefined) {
    if (item && !items.some((existingItem) => existingItem.id === item.id)) {
      items.push(item)
    }
  }

  if (selectedItem && selectedRole !== 'accessory') {
    addItem(selectedItem)
  }

  if (isExerciseContext(context)) {
    addItem(
      selectedRole === 'top'
        ? selectedItem
        : bestItem(availableItems, 'top', context, weather, profile, selectedItemId),
    )
    addItem(
      selectedRole === 'bottom'
        ? selectedItem
        : bestItem(availableItems, 'bottom', context, weather, profile, selectedItemId),
    )
    addItem(
      selectedRole === 'shoes'
        ? selectedItem
        : bestItem(availableItems, 'shoes', context, weather, profile, selectedItemId),
    )
    addItem(bestItem(availableItems, 'socks', context, weather, profile, selectedItemId))
  } else {
    const selectedIsFullBody = selectedRole === 'fullBody'
    const fullBody = selectedIsFullBody
      ? selectedItem
      : bestItem(availableItems, 'fullBody', context, weather, profile, selectedItemId)

    if (fullBody && scoreItem(fullBody, context, weather, profile) >= 54) {
      addItem(fullBody)
    } else {
      addItem(
        selectedRole === 'top'
          ? selectedItem
          : bestItem(availableItems, 'top', context, weather, profile, selectedItemId),
      )
      addItem(
        selectedRole === 'bottom'
          ? selectedItem
          : bestItem(availableItems, 'bottom', context, weather, profile, selectedItemId),
      )
    }

    addItem(
      selectedRole === 'shoes'
        ? selectedItem
        : bestItem(availableItems, 'shoes', context, weather, profile, selectedItemId),
    )

    const shouldAddOuterwear =
      weather.temperatureF < 64 || weather.isRaining || /rain|storm|wind/i.test(weather.condition)
    if (shouldAddOuterwear) {
      addItem(bestItem(availableItems, 'outerwear', context, weather, profile, selectedItemId))
    }

    const needsBelt =
      isWorkContext(context) ||
      (hasCollaredTop(items) && items.some((item) => itemRole(item) === 'bottom' && hasBeltLoops(item)))
    if (needsBelt) {
      addItem(bestItem(availableItems, 'belt', context, weather, profile, selectedItemId))
    }
  }

  if (selectedItem && selectedRole === 'accessory') {
    addItem(selectedItem)
  }

  return scoreOutfit(items, {
    context,
    profile,
    source: 'local',
    weather,
  })
}

export function scoreCustomOutfit({
  context,
  items,
  profile,
  source = 'local',
  weather,
}: {
  context: OutfitContext
  items: ClothingItem[]
  profile: UserProfile | null
  source?: OutfitSource
  weather: WeatherInput
}) {
  return scoreOutfit(items, {
    context,
    profile,
    source,
    weather,
  })
}

export async function saveOutfitFeedback({
  context,
  feedback,
  note,
  recommendation,
  userId,
  weather,
}: {
  context: OutfitContext
  feedback: OutfitFeedbackType
  note: string
  recommendation: OutfitRecommendation
  userId: string
  weather: WeatherInput
}) {
  if (!db) {
    throw new Error('Firebase is not configured.')
  }

  await addDoc(collection(db, 'users', userId, 'outfitFeedback'), {
    type: feedback,
    note: note.trim(),
    context,
    weatherSummary: weatherSummary(weather),
    itemIDs: recommendation.items.map((item) => item.id),
    itemNames: recommendation.items.map((item) => item.name),
    score: recommendation.score,
    source: recommendation.source,
    rationale: recommendation.rationale,
    createdAt: serverTimestamp(),
  })
}

export function weatherSummary(weather: WeatherInput) {
  const parts = [
    weather.location.trim() || 'Unknown location',
    `${weather.temperatureF}F`,
    weather.condition.trim() || 'Weather not specified',
    weather.isRaining ? 'rain' : null,
    `humidity ${weather.humidityPercent}%`,
    `wind ${weather.windMph} mph`,
  ].filter(Boolean)

  return parts.join(' - ')
}

async function requestAIOutfit(request: OutfitGenerationRequest): Promise<OutfitRecommendation> {
  const settings = getAIProxySettings()
  const baseURL = settings.proxyUrl.trim().replace(/\/+$/, '')

  if (!baseURL) {
    throw new Error('AI proxy URL is not configured in More.')
  }

  const recentFeedback = await loadRecentFeedback(request.userId)
  const contextStyles = await loadContextStyles(request.userId)
  const localCandidate = generateLocalOutfit({ ...request, askAIFirst: false })
  const selectedContext = contextDetails(request.context, contextOptionsFromSettings(contextStyles))

  const response = await fetch(`${baseURL}/outfit-recommendation`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(settings.proxyToken.trim() ? { 'X-FitCheck-Token': settings.proxyToken.trim() } : {}),
    },
    body: JSON.stringify({
      closet: request.closet
        .filter((item) => item.status === 'active')
        .map((item) => ({
          id: item.id,
          name: item.name,
          brand: item.brand,
          category: item.category,
          color: item.color,
          material: item.material,
          quantity: item.quantity,
          pattern: item.pattern,
          formalityLevel: inferredFormality(item),
          weatherSuitability: inferredWeatherSuitability(item),
          occasionSuitability: inferredOccasionSuitability(item),
          activitySuitability: inferredActivitySuitability(item),
          notes: item.notes,
        })),
      weatherSummary: weatherSummary(request.weather),
      context: selectedContext.value,
      contextLabel: selectedContext.label,
      contextDefinition: selectedContext.description,
      occasion: selectedContext.label,
      activity: selectedContext.value,
      styleDescription: [
        profileStyleSummary(request.profile),
        `Selected context: ${selectedContext.label}`,
        `Selected context definition: ${selectedContext.description}`,
        'Context style definitions:',
        contextStylesPrompt(contextStyles),
      ]
        .filter(Boolean)
        .join('\n\n'),
      selectedItemID: request.selectedItemId ?? null,
      candidateItemIDs: [],
      localScore: localCandidate.score,
      localNotes: localCandidate.reasons,
      recentFeedback,
    }),
  })

  const data = await response.json().catch(() => ({}))

  if (!response.ok) {
    throw new Error(typeof data.error === 'string' ? data.error : 'AI proxy request failed.')
  }

  const itemIDs: string[] = Array.isArray(data.itemIDs)
    ? data.itemIDs.map((id: unknown) => String(id))
    : []
  const items = itemIDs
    .map((id: string) =>
      request.closet.find((item: ClothingItem) => item.id === id && item.status === 'active'),
    )
    .filter((item): item is ClothingItem => Boolean(item))

  const scored = scoreOutfit(items, {
    context: request.context,
    profile: request.profile,
    source: 'ai',
    weather: request.weather,
  })

  return {
    ...scored,
    rationale: String(data.rationale ?? 'AI selected this from your closet.'),
    cautions: Array.isArray(data.cautions)
      ? data.cautions.map(String).slice(0, 5)
      : scored.cautions,
  }
}

async function loadRecentFeedback(userId: string) {
  if (!db) {
    return []
  }

  const snapshot = await getDocs(collection(db, 'users', userId, 'outfitFeedback'))
  return snapshot.docs
    .map((feedbackSnapshot) => {
      const data = feedbackSnapshot.data()
      const createdAt = data.createdAt as { toMillis?: () => number } | undefined
      return {
        text: [
          typeof data.type === 'string' ? data.type : 'feedback',
          typeof data.context === 'string' ? data.context : '',
          Array.isArray(data.itemNames) ? data.itemNames.join(', ') : '',
          typeof data.note === 'string' ? data.note : '',
        ]
          .filter(Boolean)
          .join(': '),
        createdAt: createdAt?.toMillis?.() ?? 0,
      }
    })
    .sort((first, second) => second.createdAt - first.createdAt)
    .slice(0, 12)
    .map((feedback) => feedback.text)
}

function scoreOutfit(
  items: ClothingItem[],
  {
    context,
    profile,
    source,
    weather,
  }: {
    context: OutfitContext
    profile: UserProfile | null
    source: OutfitSource
    weather: WeatherInput
  },
): OutfitRecommendation {
  const reasons: string[] = []
  const cautions: string[] = []
  let score = 62
  const roles = items.map(itemRole)
  const hasTopBottom = roles.includes('top') && roles.includes('bottom')
  const hasDress = roles.includes('fullBody')
  const hasShoes = roles.includes('shoes')

  if ((hasTopBottom || hasDress) && hasShoes) {
    score += 14
    reasons.push('Has the core clothing roles covered.')
  } else {
    score -= 22
    cautions.push('Missing a core role such as top, bottom, dress, or shoes.')
  }

  for (const item of items) {
    const itemScore = scoreItem(item, context, weather, profile)
    score += (itemScore - 58) / 4
  }

  if (isWorkContext(context)) {
    if (items.some(isShorts)) {
      score -= 30
      cautions.push('Shorts weaken a work outfit.')
    }
    if (items.some(isSweatsOrJoggers)) {
      score -= 36
      cautions.push('Sweats or joggers are not workwear.')
    }
    if (items.some(isCasualOnlyFootwear)) {
      score -= 34
      cautions.push('Casual clogs, slides, or slippers do not work for office wear.')
    }
  }

  if (isExerciseContext(context)) {
    if (items.some((item) => item.category === 'belt' || item.category === 'watch' || item.category === 'jewelry')) {
      score -= 28
      cautions.push('Workout outfits should not include belts, watches, jewelry, or dress accessories.')
    }
    if (items.some((item) => /button-down|button down|collar|chino|trouser|leather|dress/.test(itemText(item)))) {
      score -= 30
      cautions.push('Workout contexts need exercise clothing, not office or dress pieces.')
    }
    if (isRunningContext(context) && !items.some((item) => /running shoe|run shoe|runner/.test(itemText(item)))) {
      score -= 12
      cautions.push('Running works best with running-specific shoes.')
    }
    if (isRunningContext(context) && items.some((item) => item.category === 'socks' && /run|running/.test(itemText(item)))) {
      score += 6
      reasons.push('Running socks support the running context.')
    }
  }

  if (context === 'goingOut') {
    if (items.some(isSweatsOrJoggers)) {
      score -= 24
      cautions.push('Sweats or joggers weaken a going-out outfit.')
    }
    if (items.some(isCasualOnlyFootwear)) {
      score -= 18
      cautions.push('Very casual footwear is usually too relaxed for going out.')
    }
  }

  if (context === 'coastalCasual') {
    if (items.some((item) => /flip-flop|flip flop|sandal|shorts|tank|linen|cotton|tee|t-shirt/.test(itemText(item)))) {
      score += 10
      reasons.push('Relaxed beach-town pieces fit coastal casual.')
    }
  }

  if (items.some(isShorts) && items.some(isBoots)) {
    score -= 32
    cautions.push('Shorts with boots is usually not a polished combination.')
  }

  if (items.some(isSweatsOrJoggers) && items.some(isBoots)) {
    score -= 34
    cautions.push('Sweats or joggers should not be paired with leather boots.')
  }

  if (items.some((item) => item.category === 'belt') && items.some(isSweatsOrJoggers)) {
    score -= 26
    cautions.push('A belt does not make sense with sweatpants or joggers.')
  }

  if (hasCollaredTop(items)) {
    if (items.some((item) => item.category === 'belt')) {
      score += 7
      reasons.push('Belt supports the collared shirt and tailored bottom.')
    } else if (items.some((item) => itemRole(item) === 'bottom' && hasBeltLoops(item))) {
      score -= 8
      cautions.push('A belt would improve this collared-shirt outfit.')
    }
  }

  const colorNote = colorHarmonyNote(items)
  score += colorNote.scoreAdjustment
  if (colorNote.reason) {
    reasons.push(colorNote.reason)
  }
  if (colorNote.caution) {
    cautions.push(colorNote.caution)
  }

  if (weather.temperatureF >= 85 && weather.humidityPercent >= 55) {
    if (items.some((item) => item.category === 'jacket' || item.category === 'sweater')) {
      score -= 18
      cautions.push('Hot, humid weather argues against extra layers.')
    }
    if (items.some(isHeatFriendly)) {
      score += 8
      reasons.push('Uses at least one heat-friendly piece.')
    }
  }

  if (weather.isRaining && items.some(isRainFriendly)) {
    score += 5
    reasons.push('Includes a rain-friendly item.')
  }

  const boundedScore = Math.max(0, Math.min(100, Math.round(score)))
  const uniqueReasons = [...new Set(reasons)].slice(0, 6)
  const uniqueCautions = [...new Set(cautions)].slice(0, 5)

  return {
    id: crypto.randomUUID(),
    items,
    score: boundedScore,
    scoreLabel: scoreLabel(boundedScore),
    source,
    rationale:
      source === 'ai'
        ? 'AI selected this from your closet; FitCheck scored the result locally.'
        : 'FitCheck built this from your active closet with local scoring.',
    reasons: uniqueReasons.length > 0 ? uniqueReasons : ['Best available match from your closet.'],
    cautions: uniqueCautions,
  }
}

function bestItem(
  items: ClothingItem[],
  role: ItemRole,
  context: OutfitContext,
  weather: WeatherInput,
  profile: UserProfile | null,
  selectedItemId?: string,
) {
  const candidates = items.filter((item) => item.id !== selectedItemId && itemRole(item) === role)
  const relaxedCandidates =
    candidates.length > 0
      ? candidates
      : items.filter((item) => item.id !== selectedItemId && relaxedRole(item, role, context))

  return relaxedCandidates
    .map((item) => ({ item, score: scoreItem(item, context, weather, profile) }))
    .sort((first, second) => second.score - first.score)[0]?.item
}

function scoreItem(
  item: ClothingItem,
  context: OutfitContext,
  weather: WeatherInput,
  profile: UserProfile | null,
) {
  let score = 50
  const text = itemText(item)
  const role = itemRole(item)

  if (isExerciseContext(context)) {
    if (/run|running|lifting|training|gym|workout|dri|athletic|performance|compression|sport/.test(text)) {
      score += 22
    }
    if (isRunningContext(context) && /run|running|runner|running sock|running shoe|reflective/.test(text)) {
      score += 14
    }
    if (isLiftingContext(context) && /lift|lifting|training|trainer|gym|mobility|workout/.test(text)) {
      score += 12
    }
    if (role === 'belt' || /leather|dress|chino|trouser|button-down|button down|collar/.test(text)) {
      score -= 24
    }
  }

  if (isWorkContext(context)) {
    if (/button|collar|polo|chino|trouser|oxford|loafer|boot|leather|belt|blazer/.test(text)) {
      score += 18
    }
    if (/sweat|jogger|track|gym|running|crocs|clog|slide|slipper/.test(text)) {
      score -= 28
    }
  }

  if (context === 'travel') {
    if (/sneaker|tee|t-shirt|shirt|chino|pant|jogger|comfortable|stretch|travel|wrinkle|soft|layer/.test(text)) {
      score += 14
    }
    if (/stiff|formal|heel|heavy/.test(text)) {
      score -= 8
    }
  }

  if (context === 'casual') {
    if (/sneaker|tee|t-shirt|shirt|short|chino|jean|comfortable|stretch/.test(text)) {
      score += 12
    }
    if (/sweatpant|slipper|pajama/.test(text)) {
      score -= 8
    }
  }

  if (context === 'coastalCasual') {
    if (/flip-flop|flip flop|sandal|short|tank|tee|t-shirt|linen|cotton|swim|beach/.test(text)) {
      score += 18
    }
    if (/boot|blazer|wool|heavy|formal/.test(text)) {
      score -= 12
    }
  }

  if (context === 'lounge') {
    if (/sweat|jogger|hoodie|legging|soft|lounge|pajama|slide|slipper|tee|t-shirt/.test(text)) {
      score += 18
    }
    if (/dress shoe|loafer|blazer|stiff|formal/.test(text)) {
      score -= 12
    }
  }

  if (context === 'goingOut') {
    if (/button|collar|sweater|dress|skirt|chino|trouser|leather|loafer|boot/.test(text)) {
      score += 15
    }
    if (/jewelry|watch|polished|fitted|dark/.test(text)) {
      score += 8
    }
    if (/sweat|gym|running|compression|flip-flop|flip flop|slipper/.test(text)) {
      score -= 18
    }
  }

  if (context === 'exploring') {
    if (/sneaker|walking|walkable|comfortable|breathable|short|chino|jean|hat|sunglass|layer/.test(text)) {
      score += 14
    }
    if (/stiff|formal|heel|slipper/.test(text)) {
      score -= 10
    }
  }

  if (context === 'outdoorRecreation') {
    if (/outdoor|hiking|trail|sturdy|sun|hat|breathable|performance|sandal|short|layer|dust|beach|lake/.test(text)) {
      score += 16
    }
    if (/dress|loafer|heel|formal|silk/.test(text)) {
      score -= 14
    }
  }

  if (weather.temperatureF >= 85) {
    if (isHeatFriendly(item)) {
      score += 16
    }
    if (/heavy|fleece|wool|jacket|sweater|boot/.test(text) && !/merino|lightweight/.test(text)) {
      score -= 16
    }
  } else if (weather.temperatureF < 62) {
    if (/jacket|sweater|wool|pants|boot/.test(text)) {
      score += 12
    }
    if (/short sleeve|shorts|linen/.test(text)) {
      score -= 10
    }
  }

  if (weather.isRaining || /rain|storm/.test(weather.condition.toLowerCase())) {
    if (isRainFriendly(item)) {
      score += 14
    }
    if (/suede|white sneaker|canvas/.test(text)) {
      score -= 8
    }
  }

  const styleText = profileStyleSummary(profile).toLowerCase()
  if (styleText) {
    if (styleText.includes('runs hot') && weather.temperatureF >= 74 && isHeatFriendly(item)) {
      score += 8
    }
    if (styleText.includes('no shorts for work') && isWorkContext(context) && isShorts(item)) {
      score -= 28
    }
    if (styleText.includes('no shorts with boots') && (isShorts(item) || isBoots(item))) {
      score -= 4
    }
  }

  if (profile?.temperatureSensitivity === 'runs_hot' && weather.temperatureF >= 74) {
    if (isHeatFriendly(item)) {
      score += 7
    }
    if (/jacket|sweater|fleece|heavy/.test(text)) {
      score -= 10
    }
  }

  if (profile?.temperatureSensitivity === 'runs_cold' && weather.temperatureF <= 76) {
    if (/pants|sweater|jacket|wool|merino|layer/.test(text)) {
      score += 7
    }
    if (/shorts|tank|sleeveless/.test(text)) {
      score -= 7
    }
  }

  score -= recentWearPenalty(item)

  return score
}

function recentWearPenalty(item: ClothingItem) {
  if (!item.lastWornAt || item.category === 'belt' || item.category === 'watch') {
    return 0
  }

  const daysSinceWorn = Math.floor(
    (Date.now() - new Date(item.lastWornAt).getTime()) / (1000 * 60 * 60 * 24),
  )

  if (!Number.isFinite(daysSinceWorn) || daysSinceWorn < 0) {
    return 0
  }

  if (daysSinceWorn === 0) return 18
  if (daysSinceWorn === 1) return 14
  if (daysSinceWorn <= 3) return 9
  if (daysSinceWorn <= 6) return 5
  return 0
}

function itemRole(item: ClothingItem): ItemRole {
  const text = itemText(item)

  switch (item.category) {
    case 'shirt':
    case 'blouse':
    case 'sweater':
      return 'top'
    case 'pants':
    case 'shorts':
    case 'skirt':
      return 'bottom'
    case 'dress':
      return 'fullBody'
    case 'shoes':
    case 'heels':
    case 'flats':
      return 'shoes'
    case 'jacket':
      return 'outerwear'
    case 'belt':
      return 'belt'
    case 'socks':
      return 'socks'
    case 'activewear':
      if (/short|pants|jogger|tight|legging|bottom/.test(text)) {
        return 'bottom'
      }
      return 'top'
    case 'watch':
    case 'jewelry':
    case 'accessory':
    case 'bag':
    case 'purse':
    case 'underwear':
    case 'other':
      return 'accessory'
  }
}

function relaxedRole(item: ClothingItem, targetRole: ItemRole, context: OutfitContext) {
  if (targetRole === 'top' && !isExerciseContext(context)) {
    return item.category === 'activewear' && /shirt|top|tee|tank/.test(itemText(item))
  }

  if (targetRole === 'bottom' && !isWorkContext(context)) {
    return item.category === 'activewear' && /short|pant|jogger|tight|legging/.test(itemText(item))
  }

  return false
}

function itemText(item: ClothingItem) {
  return [item.name, item.brand, item.color, item.material, item.pattern, categoryLabel(item.category), item.notes]
    .join(' ')
    .toLowerCase()
}

function isHeatFriendly(item: ClothingItem) {
  return /linen|cotton|dri|dry|tech|performance|short sleeve|t-shirt|tee|shorts|lightweight|breathable/.test(
    itemText(item),
  )
}

function isRainFriendly(item: ClothingItem) {
  return /rain|shell|waterproof|water resistant|gore-tex|storm/.test(itemText(item))
}

function isShorts(item: ClothingItem) {
  return item.category === 'shorts' || /\bshorts\b/.test(itemText(item))
}

function isBoots(item: ClothingItem) {
  return /boot/.test(itemText(item))
}

function isSweatsOrJoggers(item: ClothingItem) {
  return /sweatpant|sweat pant|jogger|track pant|lounge/.test(itemText(item))
}

function isCasualOnlyFootwear(item: ClothingItem) {
  return /crocs|clog|slide|slipper|flip-flop|flip flop/.test(itemText(item))
}

function hasCollaredTop(items: ClothingItem[]) {
  return items.some((item) => itemRole(item) === 'top' && /collar|button|polo|oxford/.test(itemText(item)))
}

function hasBeltLoops(item: ClothingItem) {
  return item.category === 'pants' || item.category === 'shorts' || /chino|jean|trouser/.test(itemText(item))
}

function colorHarmonyNote(items: ClothingItem[]) {
  const colors = items
    .map((item) => colorFamily(item.color || item.name))
    .filter((color): color is string => Boolean(color))
  const uniqueColors = [...new Set(colors)]
  const boldColors = uniqueColors.filter((color) => !['black', 'white', 'gray', 'navy', 'brown', 'khaki'].includes(color))

  if (uniqueColors.length <= 3 && boldColors.length <= 1) {
    return { scoreAdjustment: 8, reason: 'Color palette stays focused.', caution: null }
  }

  if (boldColors.length > 2) {
    return { scoreAdjustment: -8, reason: null, caution: 'Multiple bold colors may compete.' }
  }

  return { scoreAdjustment: 0, reason: null, caution: null }
}

function colorFamily(text: string) {
  const normalized = text.toLowerCase()
  const knownColors = [
    'black',
    'white',
    'gray',
    'grey',
    'navy',
    'blue',
    'brown',
    'khaki',
    'beige',
    'green',
    'olive',
    'red',
    'salmon',
    'pink',
    'orange',
    'yellow',
  ]
  const match = knownColors.find((color) => normalized.includes(color))

  if (match === 'grey') {
    return 'gray'
  }

  if (match === 'beige') {
    return 'khaki'
  }

  return match
}

function inferredFormality(item: ClothingItem) {
  const text = itemText(item)
  if (/blazer|suit|dress|heel|loafer|oxford/.test(text)) return 5
  if (/button|collar|chino|trouser|leather|boot|belt/.test(text)) return 4
  if (/tee|sneaker|jean|short/.test(text)) return 2
  if (/gym|running|sweat|jogger|compression/.test(text)) return 1
  return 3
}

function inferredWeatherSuitability(item: ClothingItem) {
  const tags: string[] = []
  if (isHeatFriendly(item)) tags.push('hot')
  if (isRainFriendly(item)) tags.push('rain')
  if (/wool|sweater|jacket|fleece|boot/.test(itemText(item))) tags.push('cool')
  return tags.join(', ')
}

function inferredOccasionSuitability(item: ClothingItem) {
  const text = itemText(item)
  const tags: string[] = []
  if (/button|collar|chino|trouser|leather|belt|loafer|boot/.test(text)) tags.push('work')
  if (/tee|sneaker|short|jean|casual/.test(text)) tags.push('casual')
  if (/flip-flop|flip flop|sandal|linen|tank|beach/.test(text)) tags.push('coastal casual')
  if (/sweat|jogger|hoodie|lounge|soft/.test(text)) tags.push('lounge')
  if (/dress|dinner|date|sweater|jewelry|watch/.test(text)) tags.push('going out')
  return tags.join(', ')
}

function inferredActivitySuitability(item: ClothingItem) {
  const text = itemText(item)
  const tags: string[] = []
  if (/lifting|training|gym|compression|dri/.test(text)) tags.push('lifting')
  if (/run|running|runner/.test(text)) tags.push('running')
  if (/travel|stretch|comfortable|sneaker/.test(text)) tags.push('travel')
  if (/walking|sneaker|short|tee/.test(text)) tags.push('exploring')
  if (/hiking|trail|outdoor|beach|lake|sun/.test(text)) tags.push('outdoor recreation')
  return tags.join(', ')
}

function scoreLabel(score: number) {
  if (score >= 84) return 'Excellent'
  if (score >= 70) return 'Strong'
  if (score >= 54) return 'Usable'
  return 'Weak'
}

export function categoryName(category: ClothingCategory) {
  return categoryLabel(category)
}
