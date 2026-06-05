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
  normalizeOutfitContext,
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
export type FeedbackSignalType = 'liked_combo' | 'rejected_combo' | 'issue_combo'

export type ScoreBreakdownComponent = {
  delta: number
  kind: 'base' | 'bonus' | 'item' | 'penalty'
  label: string
  scoreAfter: number
}

export type ItemScoreBreakdown = {
  categoryLabel: string
  components: ScoreBreakdownComponent[]
  contributionToOutfit: number
  itemID: string
  itemName: string
  rawScore: number
}

export type OutfitScoreBreakdown = {
  finalScore: number
  itemBreakdowns: ItemScoreBreakdown[]
  outfitComponents: ScoreBreakdownComponent[]
  rawScore: number
  startingScore: number
}

export type FeedbackLearningSignal = {
  type: FeedbackSignalType
  context: OutfitContext
  itemIDs: string[]
  itemPairKeys: string[]
  note: string
  createdAt: number
}

export type WeatherInput = {
  location: string
  temperatureF: number
  highTemperatureF: number
  lowTemperatureF: number
  condition: string
  isRaining: boolean
  humidityPercent: number
  windMph: number
  source?: string
}

export type OutfitRecommendation = {
  id: string
  items: ClothingItem[]
  score: number
  scoreBreakdown: OutfitScoreBreakdown
  scoreLabel: string
  source: OutfitSource
  rationale: string
  reasons: string[]
  cautions: string[]
}

export type OutfitGenerationRequest = {
  closet: ClothingItem[]
  context: OutfitContext
  feedbackSignals?: FeedbackLearningSignal[]
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
  highTemperatureF: 75,
  lowTemperatureF: 75,
  condition: 'Clear',
  isRaining: false,
  humidityPercent: 45,
  windMph: 5,
}

export async function generateOutfit(
  request: OutfitGenerationRequest,
): Promise<OutfitRecommendation> {
  const feedbackSignals = request.feedbackSignals ?? (await loadFeedbackLearningSignals(request.userId))
  const requestWithSignals = {
    ...request,
    feedbackSignals,
  }
  const localRecommendation = generateLocalOutfit(requestWithSignals)

  if (!request.askAIFirst) {
    return localRecommendation
  }

  try {
    const aiRecommendation = await requestAIOutfit(requestWithSignals)
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
  feedbackSignals = [],
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
        : bestItem(availableItems, 'top', context, weather, profile, selectedItemId, feedbackSignals),
    )
    addItem(
      selectedRole === 'bottom'
        ? selectedItem
        : bestItem(availableItems, 'bottom', context, weather, profile, selectedItemId, feedbackSignals),
    )
    addItem(
      selectedRole === 'shoes'
        ? selectedItem
        : bestItem(availableItems, 'shoes', context, weather, profile, selectedItemId, feedbackSignals),
    )
    addItem(bestItem(availableItems, 'socks', context, weather, profile, selectedItemId, feedbackSignals))
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
          : bestItem(availableItems, 'top', context, weather, profile, selectedItemId, feedbackSignals),
      )
      addItem(
        selectedRole === 'bottom'
          ? selectedItem
          : bestItem(availableItems, 'bottom', context, weather, profile, selectedItemId, feedbackSignals),
      )
    }

    addItem(
      selectedRole === 'shoes'
        ? selectedItem
        : bestItem(availableItems, 'shoes', context, weather, profile, selectedItemId, feedbackSignals),
    )

    const shouldAddOuterwear =
      dayLowTemperature(weather) < 64 || weather.isRaining || /rain|storm|wind/i.test(weather.condition)
    if (shouldAddOuterwear) {
      addItem(bestItem(availableItems, 'outerwear', context, weather, profile, selectedItemId, feedbackSignals))
    }

    const needsBelt =
      isWorkContext(context) ||
      (hasCollaredTop(items) && items.some((item) => itemRole(item) === 'bottom' && hasBeltLoops(item)))
    if (needsBelt) {
      addItem(bestItem(availableItems, 'belt', context, weather, profile, selectedItemId, feedbackSignals))
    }
  }

  if (selectedItem && selectedRole === 'accessory') {
    addItem(selectedItem)
  }

  return scoreOutfit(items, {
    context,
    feedbackSignals,
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

  await addDoc(collection(db, 'users', userId, 'feedbackSignals'), {
    type: feedbackSignalType(feedback),
    note: note.trim(),
    context,
    weatherSummary: weatherSummary(weather),
    itemIDs: recommendation.items.map((item) => item.id),
    itemNames: recommendation.items.map((item) => item.name),
    itemPairKeys: itemPairKeys(recommendation.items.map((item) => item.id)),
    score: recommendation.score,
    source: recommendation.source,
    createdAt: serverTimestamp(),
  })
}

export function weatherSummary(weather: WeatherInput) {
  const parts = [
    weather.location.trim() || 'Unknown location',
    `day ${temperatureRangeLabel(weather)}`,
    weather.condition.trim() || 'Weather not specified',
    weather.isRaining ? 'rain' : null,
    `humidity ${weather.humidityPercent}%`,
    `wind ${weather.windMph} mph`,
    weather.source ?? null,
  ].filter(Boolean)

  return parts.join(' - ')
}

function temperatureRangeLabel(weather: WeatherInput) {
  const low = dayLowTemperature(weather)
  const high = dayHighTemperature(weather)

  return low === high ? `${high}F` : `${low}-${high}F`
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

  const completedItems = completeOutfitWithLocalFallback(items, localCandidate.items, request.context)
  const scored = scoreOutfit(completedItems, {
    context: request.context,
    feedbackSignals: request.feedbackSignals ?? [],
    profile: request.profile,
    source: 'ai',
    weather: request.weather,
  })
  const repairCautions =
    completedItems.length > items.length
      ? ['AI omitted a required role, so FitCheck completed the outfit with local scorer picks.']
      : []

  return {
    ...scored,
    rationale: String(data.rationale ?? 'AI selected this from your closet.'),
    cautions: Array.isArray(data.cautions)
      ? [...repairCautions, ...data.cautions.map(String), ...scored.cautions].slice(0, 5)
      : [...repairCautions, ...scored.cautions].slice(0, 5),
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

async function loadFeedbackLearningSignals(userId: string): Promise<FeedbackLearningSignal[]> {
  if (!db) {
    return []
  }

  const snapshot = await getDocs(collection(db, 'users', userId, 'feedbackSignals'))
  return snapshot.docs
    .map((feedbackSnapshot) => {
      const data = feedbackSnapshot.data()
      const createdAt = data.createdAt as { toMillis?: () => number } | undefined
      return {
        type: feedbackSignalType(data.type),
        context: normalizeOutfitContext(data.context),
        itemIDs: stringArray(data.itemIDs),
        itemPairKeys: stringArray(data.itemPairKeys),
        note: typeof data.note === 'string' ? data.note : '',
        createdAt: createdAt?.toMillis?.() ?? 0,
      }
    })
    .sort((first, second) => second.createdAt - first.createdAt)
    .slice(0, 80)
}

function feedbackSignalType(value: unknown): FeedbackSignalType {
  if (value === 'liked') return 'liked_combo'
  if (value === 'rejected') return 'rejected_combo'
  if (value === 'issue') return 'issue_combo'
  if (value === 'liked_combo' || value === 'rejected_combo' || value === 'issue_combo') {
    return value
  }

  return 'issue_combo'
}

function itemPairKeys(itemIDs: string[]) {
  const uniqueIDs = [...new Set(itemIDs)].sort()
  const keys: string[] = []

  for (let firstIndex = 0; firstIndex < uniqueIDs.length; firstIndex += 1) {
    for (let secondIndex = firstIndex + 1; secondIndex < uniqueIDs.length; secondIndex += 1) {
      keys.push(`${uniqueIDs[firstIndex]}::${uniqueIDs[secondIndex]}`)
    }
  }

  return keys
}

function stringArray(value: unknown) {
  return Array.isArray(value) ? value.map(String).filter(Boolean) : []
}

function roundScore(value: number) {
  return Math.round(value * 10) / 10
}

function scoreOutfit(
  items: ClothingItem[],
  {
    context,
    feedbackSignals = [],
    profile,
    source,
    weather,
  }: {
    context: OutfitContext
    feedbackSignals?: FeedbackLearningSignal[]
    profile: UserProfile | null
    source: OutfitSource
    weather: WeatherInput
  },
): OutfitRecommendation {
  const reasons: string[] = []
  const cautions: string[] = []
  const startingScore = 62
  let score = startingScore
  const outfitComponents: ScoreBreakdownComponent[] = [
    {
      delta: startingScore,
      kind: 'base',
      label: 'Base outfit score before context, weather, fashion, and feedback checks',
      scoreAfter: startingScore,
    },
  ]
  const itemBreakdowns: ItemScoreBreakdown[] = []
  const roles = items.map(itemRole)
  const hasTopBottom = roles.includes('top') && roles.includes('bottom')
  const hasDress = roles.includes('fullBody')
  const hasShoes = roles.includes('shoes')

  function addOutfitScore(delta: number, label: string, kind?: ScoreBreakdownComponent['kind']) {
    if (delta === 0) {
      return
    }

    score += delta
    outfitComponents.push({
      delta: roundScore(delta),
      kind: kind ?? (delta > 0 ? 'bonus' : 'penalty'),
      label,
      scoreAfter: roundScore(score),
    })
  }

  if ((hasTopBottom || hasDress) && hasShoes) {
    addOutfitScore(14, 'Core roles covered: top/bottom or dress plus shoes')
    reasons.push('Has the core clothing roles covered.')
  } else {
    addOutfitScore(-22, 'Missing a core role such as top, bottom, dress, or shoes')
    cautions.push('Missing a core role such as top, bottom, dress, or shoes.')
  }

  for (const item of items) {
    const itemBreakdown = scoreItemBreakdown(item, context, weather, profile)
    const contributionToOutfit = (itemBreakdown.rawScore - 58) / 4
    itemBreakdowns.push({
      ...itemBreakdown,
      contributionToOutfit: roundScore(contributionToOutfit),
    })
    addOutfitScore(
      contributionToOutfit,
      `${item.name}: item score ${itemBreakdown.rawScore}/100 contributes to outfit`,
      'item',
    )
  }

  if (isWorkContext(context)) {
    if (items.some(isShorts)) {
      addOutfitScore(-30, 'Work context penalty: shorts weaken a work outfit')
      cautions.push('Shorts weaken a work outfit.')
    }
    if (items.some(isSweatsOrJoggers)) {
      addOutfitScore(-36, 'Work context penalty: sweats or joggers are not workwear')
      cautions.push('Sweats or joggers are not workwear.')
    }
    if (items.some(isCasualOnlyFootwear)) {
      addOutfitScore(-34, 'Work context penalty: casual-only footwear is not office appropriate')
      cautions.push('Casual clogs, slides, or slippers do not work for office wear.')
    }
  }

  if (isExerciseContext(context)) {
    if (items.some((item) => item.category === 'belt' || item.category === 'watch' || item.category === 'jewelry')) {
      addOutfitScore(-28, 'Workout penalty: belts, watches, jewelry, or dress accessories included')
      cautions.push('Workout outfits should not include belts, watches, jewelry, or dress accessories.')
    }
    if (items.some((item) => /button-down|button down|collar|chino|trouser|leather|dress/.test(itemText(item)))) {
      addOutfitScore(-30, 'Workout penalty: office or dress pieces included')
      cautions.push('Workout contexts need exercise clothing, not office or dress pieces.')
    }
    if (isRunningContext(context) && !items.some((item) => /running shoe|run shoe|runner/.test(itemText(item)))) {
      addOutfitScore(-12, 'Running penalty: no running-specific shoes found')
      cautions.push('Running works best with running-specific shoes.')
    }
    if (isRunningContext(context) && items.some((item) => item.category === 'socks' && /run|running/.test(itemText(item)))) {
      addOutfitScore(6, 'Running bonus: running socks included')
      reasons.push('Running socks support the running context.')
    }
  }

  if (context === 'goingOut') {
    if (items.some(isSweatsOrJoggers)) {
      addOutfitScore(-24, 'Going-out penalty: sweats or joggers weaken the outfit')
      cautions.push('Sweats or joggers weaken a going-out outfit.')
    }
    if (items.some(isCasualOnlyFootwear)) {
      addOutfitScore(-18, 'Going-out penalty: footwear is too relaxed')
      cautions.push('Very casual footwear is usually too relaxed for going out.')
    }
  }

  if (context === 'coastalCasual') {
    if (items.some((item) => /flip-flop|flip flop|sandal|shorts|tank|linen|cotton|tee|t-shirt/.test(itemText(item)))) {
      addOutfitScore(10, 'Coastal casual bonus: relaxed beach-town pieces included')
      reasons.push('Relaxed beach-town pieces fit coastal casual.')
    }
  }

  if (items.some(isShorts) && items.some(isBoots)) {
    addOutfitScore(-32, 'Fashion rule penalty: shorts with boots is rarely polished')
    cautions.push('Shorts with boots is usually not a polished combination.')
  }

  if (items.some(isSweatsOrJoggers) && items.some(isBoots)) {
    addOutfitScore(-34, 'Fashion rule penalty: sweats or joggers with leather boots')
    cautions.push('Sweats or joggers should not be paired with leather boots.')
  }

  if (items.some((item) => item.category === 'belt') && items.some(isSweatsOrJoggers)) {
    addOutfitScore(-26, 'Function rule penalty: belt with sweatpants or joggers')
    cautions.push('A belt does not make sense with sweatpants or joggers.')
  }

  if (hasCollaredTop(items)) {
    if (items.some((item) => item.category === 'belt')) {
      addOutfitScore(7, 'Collared shirt bonus: belt supports tailored bottom')
      reasons.push('Belt supports the collared shirt and tailored bottom.')
    } else if (items.some((item) => itemRole(item) === 'bottom' && hasBeltLoops(item))) {
      addOutfitScore(-8, 'Collared shirt penalty: belt would improve this outfit')
      cautions.push('A belt would improve this collared-shirt outfit.')
    }
  }

  const colorNote = colorHarmonyNote(items)
  addOutfitScore(colorNote.scoreAdjustment, colorNote.reason ?? colorNote.caution ?? 'Color palette adjustment')
  if (colorNote.reason) {
    reasons.push(colorNote.reason)
  }
  if (colorNote.caution) {
    cautions.push(colorNote.caution)
  }

  if (dayHighTemperature(weather) >= 85 && weather.humidityPercent >= 55) {
    if (items.some((item) => item.category === 'jacket' || item.category === 'sweater')) {
      addOutfitScore(-18, 'Weather penalty: hot, humid day argues against extra layers')
      cautions.push('Hot, humid weather argues against extra layers.')
    }
    if (items.some(isHeatFriendly)) {
      addOutfitScore(8, 'Weather bonus: heat-friendly piece included')
      reasons.push('Uses at least one heat-friendly piece.')
    }
  }

  if (weather.isRaining && items.some(isRainFriendly)) {
    addOutfitScore(5, 'Weather bonus: rain-friendly item included')
    reasons.push('Includes a rain-friendly item.')
  }

  const qualityReview = reviewOutfitQuality(items, { context, profile, weather })
  addOutfitScore(qualityReview.scoreAdjustment, 'Quality review total adjustment')
  reasons.push(...qualityReview.reasons)
  cautions.push(...qualityReview.cautions)

  const feedbackReview = reviewFeedbackSignals(items, context, feedbackSignals)
  addOutfitScore(feedbackReview.scoreAdjustment, 'Feedback learning total adjustment')
  reasons.push(...feedbackReview.reasons)
  cautions.push(...feedbackReview.cautions)

  const rawScore = roundScore(score)
  const boundedScore = Math.max(0, Math.min(100, Math.round(score)))
  if (boundedScore !== Math.round(rawScore)) {
    outfitComponents.push({
      delta: roundScore(boundedScore - rawScore),
      kind: boundedScore > rawScore ? 'bonus' : 'penalty',
      label: 'Final score clamped to 0-100 range',
      scoreAfter: boundedScore,
    })
  }
  const uniqueReasons = [...new Set(reasons)].slice(0, 6)
  const uniqueCautions = [...new Set(cautions)].slice(0, 5)

  return {
    id: crypto.randomUUID(),
    items,
    score: boundedScore,
    scoreBreakdown: {
      finalScore: boundedScore,
      itemBreakdowns,
      outfitComponents,
      rawScore,
      startingScore,
    },
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
  feedbackSignals: FeedbackLearningSignal[] = [],
) {
  const candidates = items.filter((item) => item.id !== selectedItemId && itemRole(item) === role)
  const relaxedCandidates =
    candidates.length > 0
      ? candidates
      : items.filter((item) => item.id !== selectedItemId && relaxedRole(item, role, context))

  return relaxedCandidates
    .map((item) => ({
      item,
      score: scoreItem(item, context, weather, profile) + itemFeedbackAdjustment(item, context, feedbackSignals),
    }))
    .sort((first, second) => second.score - first.score)[0]?.item
}

function reviewOutfitQuality(
  items: ClothingItem[],
  {
    context,
    profile,
    weather,
  }: {
    context: OutfitContext
    profile: UserProfile | null
    weather: WeatherInput
  },
) {
  const reasons: string[] = []
  const cautions: string[] = []
  let scoreAdjustment = 0
  const roles = items.map(itemRole)
  const hasTop = roles.includes('top')
  const hasBottom = roles.includes('bottom')
  const hasFullBody = roles.includes('fullBody')
  const hasShoes = roles.includes('shoes')
  const hasCoreOutfit = ((hasTop && hasBottom) || hasFullBody) && hasShoes

  if (items.length === 0) {
    return {
      scoreAdjustment: -60,
      reasons,
      cautions: ['Quality review failed: no closet items were selected.'],
    }
  }

  if (isExerciseContext(context)) {
    if (hasTop && hasBottom && hasShoes) {
      scoreAdjustment += 10
      reasons.push('Quality review passed: workout top, bottom, and shoes are present.')
    } else {
      scoreAdjustment -= 26
      cautions.push('Quality review: workout outfits need a top, bottom, and training shoes.')
    }
  } else if (hasCoreOutfit) {
    scoreAdjustment += 10
    reasons.push('Quality review passed: top/bottom or dress plus shoes are present.')
  } else {
    scoreAdjustment -= 30
    cautions.push('Quality review: outfit is missing a required clothing role.')
  }

  if (isWorkContext(context) && items.some(isCasualOnlyFootwear)) {
    scoreAdjustment -= 22
    cautions.push('Quality review: casual-only footwear should not be used for work.')
  }

  if (isWorkContext(context) && items.some(isSweatsOrJoggers)) {
    scoreAdjustment -= 26
    cautions.push('Quality review: sweatpants and joggers are not acceptable for work.')
  }

  if (isExerciseContext(context) && items.some((item) => item.category === 'belt')) {
    scoreAdjustment -= 24
    cautions.push('Quality review: belts do not belong in workout outfits.')
  }

  if (dayHighTemperature(weather) >= 84 && weather.humidityPercent >= 55 && items.some(isInsulatingLayer)) {
    scoreAdjustment -= 18
    cautions.push('Quality review: hot, humid weather should avoid insulating layers.')
  }

  if ((weather.isRaining || /storm|rain/i.test(weather.condition)) && !items.some(isRainFriendly)) {
    cautions.push('Weather review: rain or storms are possible, but no rain-specific item is included.')
  }

  const personalReview = reviewPersonalRules(items, profile)
  scoreAdjustment += personalReview.scoreAdjustment
  cautions.push(...personalReview.cautions)

  return {
    scoreAdjustment,
    reasons,
    cautions,
  }
}

function reviewFeedbackSignals(
  items: ClothingItem[],
  context: OutfitContext,
  feedbackSignals: FeedbackLearningSignal[],
) {
  const reasons: string[] = []
  const cautions: string[] = []
  let scoreAdjustment = 0
  const itemIDs = items.map((item) => item.id)
  const currentPairKeys = itemPairKeys(itemIDs)

  for (const signal of feedbackSignals) {
    if (signal.context !== context) {
      continue
    }

    const hasExactCombo =
      signal.itemIDs.length > 0 && signal.itemIDs.every((itemID) => itemIDs.includes(itemID))
    const hasPairMatch = signal.itemPairKeys.some((pairKey) => currentPairKeys.includes(pairKey))

    if (signal.type === 'liked_combo' && (hasExactCombo || hasPairMatch)) {
      scoreAdjustment += hasExactCombo ? 12 : 5
      reasons.push('Learns from feedback: similar combo was liked before.')
    }

    if (signal.type !== 'liked_combo' && (hasExactCombo || hasPairMatch)) {
      scoreAdjustment -= hasExactCombo ? 18 : 8
      cautions.push('Learns from feedback: similar combo was previously rejected or flagged.')
    }
  }

  return {
    scoreAdjustment,
    reasons,
    cautions,
  }
}

function itemFeedbackAdjustment(
  item: ClothingItem,
  context: OutfitContext,
  feedbackSignals: FeedbackLearningSignal[],
) {
  return feedbackSignals.reduce((adjustment, signal) => {
    if (signal.context !== context || !signal.itemIDs.includes(item.id)) {
      return adjustment
    }

    if (signal.type === 'liked_combo') {
      return adjustment + 2
    }

    return adjustment - 4
  }, 0)
}

function reviewPersonalRules(items: ClothingItem[], profile: UserProfile | null) {
  const text = [profile?.rules, profile?.dislikedCombinations].filter(Boolean).join('\n').toLowerCase()
  const cautions: string[] = []
  let scoreAdjustment = 0

  if (!text) {
    return { scoreAdjustment, cautions }
  }

  if (/collared|collar|button/.test(text) && /belt/.test(text) && hasCollaredTop(items)) {
    const needsBelt = items.some((item) => itemRole(item) === 'bottom' && hasBeltLoops(item))
    const hasBelt = items.some((item) => item.category === 'belt')
    if (needsBelt && !hasBelt) {
      scoreAdjustment -= 16
      cautions.push('Personal rule review: collared shirt outfit needs a belt.')
    }
  }

  if (/shorts?.*boots?|boots?.*shorts?/.test(text) && items.some(isShorts) && items.some(isBoots)) {
    scoreAdjustment -= 24
    cautions.push('Personal rule review: shorts with boots is blocked by your style rules.')
  }

  if (/no shorts.*work|work.*no shorts/.test(text) && items.some(isShorts)) {
    scoreAdjustment -= 20
    cautions.push('Personal rule review: your work rules reject shorts.')
  }

  return { scoreAdjustment, cautions }
}

function completeOutfitWithLocalFallback(
  aiItems: ClothingItem[],
  localItems: ClothingItem[],
  context: OutfitContext,
) {
  const completedItems = [...aiItems]

  function addRole(role: ItemRole) {
    if (!completedItems.some((item) => itemRole(item) === role)) {
      const fallback = localItems.find((item) => itemRole(item) === role)
      if (fallback && !completedItems.some((item) => item.id === fallback.id)) {
        completedItems.push(fallback)
      }
    }
  }

  if (isExerciseContext(context)) {
    addRole('top')
    addRole('bottom')
    addRole('shoes')
    addRole('socks')
    return completedItems
  }

  if (!completedItems.some((item) => itemRole(item) === 'fullBody')) {
    addRole('top')
    addRole('bottom')
  }
  addRole('shoes')

  if (hasCollaredTop(completedItems)) {
    addRole('belt')
  }

  return completedItems
}

function scoreItem(
  item: ClothingItem,
  context: OutfitContext,
  weather: WeatherInput,
  profile: UserProfile | null,
) {
  return scoreItemBreakdown(item, context, weather, profile).rawScore
}

function scoreItemBreakdown(
  item: ClothingItem,
  context: OutfitContext,
  weather: WeatherInput,
  profile: UserProfile | null,
): ItemScoreBreakdown {
  let score = 50
  const components: ScoreBreakdownComponent[] = [
    {
      delta: 50,
      kind: 'base',
      label: 'Base item score before context, weather, profile, and rotation checks',
      scoreAfter: 50,
    },
  ]
  const text = itemText(item)
  const role = itemRole(item)

  function addItemScore(delta: number, label: string) {
    if (delta === 0) {
      return
    }

    score += delta
    components.push({
      delta: roundScore(delta),
      kind: delta > 0 ? 'bonus' : 'penalty',
      label,
      scoreAfter: roundScore(score),
    })
  }

  if (isExerciseContext(context)) {
    if (/run|running|lifting|training|gym|workout|dri|athletic|performance|compression|sport/.test(text)) {
      addItemScore(22, 'Exercise context match: athletic/performance wording')
    }
    if (isRunningContext(context) && /run|running|runner|running sock|running shoe|reflective/.test(text)) {
      addItemScore(14, 'Running context match: running-specific wording')
    }
    if (isLiftingContext(context) && /lift|lifting|training|trainer|gym|mobility|workout/.test(text)) {
      addItemScore(12, 'Lifting context match: gym/training wording')
    }
    if (role === 'belt' || /leather|dress|chino|trouser|button-down|button down|collar/.test(text)) {
      addItemScore(-24, 'Exercise context penalty: dress, office, or accessory item')
    }
  }

  if (isWorkContext(context)) {
    if (/button|collar|polo|chino|trouser|oxford|loafer|boot|leather|belt|blazer/.test(text)) {
      addItemScore(18, 'Work context match: polished or business-casual wording')
    }
    if (/sweat|jogger|track|gym|running|crocs|clog|slide|slipper/.test(text)) {
      addItemScore(-28, 'Work context penalty: too casual or athletic')
    }
  }

  if (context === 'travel') {
    if (/sneaker|tee|t-shirt|shirt|chino|pant|jogger|comfortable|stretch|travel|wrinkle|soft|layer/.test(text)) {
      addItemScore(14, 'Travel context match: comfortable, wrinkle-resistant, or easy to move in')
    }
    if (/stiff|formal|heel|heavy/.test(text)) {
      addItemScore(-8, 'Travel context penalty: stiff, formal, heavy, or hard to move in')
    }
  }

  if (context === 'casual') {
    if (/sneaker|tee|t-shirt|shirt|short|chino|jean|comfortable|stretch/.test(text)) {
      addItemScore(12, 'Casual context match: everyday relaxed piece')
    }
    if (/sweatpant|slipper|pajama/.test(text)) {
      addItemScore(-8, 'Casual context penalty: too lounge-specific')
    }
  }

  if (context === 'coastalCasual') {
    if (/flip-flop|flip flop|sandal|short|tank|tee|t-shirt|linen|cotton|swim|beach/.test(text)) {
      addItemScore(18, 'Coastal casual match: warm-weather beach-town piece')
    }
    if (/boot|blazer|wool|heavy|formal/.test(text)) {
      addItemScore(-12, 'Coastal casual penalty: too heavy or formal')
    }
  }

  if (context === 'lounge') {
    if (/sweat|jogger|hoodie|legging|soft|lounge|pajama|slide|slipper|tee|t-shirt/.test(text)) {
      addItemScore(18, 'Lounge context match: comfort-first piece')
    }
    if (/dress shoe|loafer|blazer|stiff|formal/.test(text)) {
      addItemScore(-12, 'Lounge context penalty: too formal or stiff')
    }
  }

  if (context === 'goingOut') {
    if (/button|collar|sweater|dress|skirt|chino|trouser|leather|loafer|boot/.test(text)) {
      addItemScore(15, 'Going-out context match: sharper or polished piece')
    }
    if (/jewelry|watch|polished|fitted|dark/.test(text)) {
      addItemScore(8, 'Going-out bonus: intentional styling detail')
    }
    if (/sweat|gym|running|compression|flip-flop|flip flop|slipper/.test(text)) {
      addItemScore(-18, 'Going-out penalty: too casual or workout-focused')
    }
  }

  if (context === 'exploring') {
    if (/sneaker|walking|walkable|comfortable|breathable|short|chino|jean|hat|sunglass|layer/.test(text)) {
      addItemScore(14, 'Exploring context match: walkable and practical')
    }
    if (/stiff|formal|heel|slipper/.test(text)) {
      addItemScore(-10, 'Exploring context penalty: stiff, formal, or impractical footwear')
    }
  }

  if (context === 'outdoorRecreation') {
    if (/outdoor|hiking|trail|sturdy|sun|hat|breathable|performance|sandal|short|layer|dust|beach|lake/.test(text)) {
      addItemScore(16, 'Outdoor recreation match: practical outdoor wording')
    }
    if (/dress|loafer|heel|formal|silk/.test(text)) {
      addItemScore(-14, 'Outdoor recreation penalty: too formal or delicate')
    }
  }

  if (dayHighTemperature(weather) >= 85) {
    if (isHeatFriendly(item)) {
      addItemScore(16, 'Weather bonus: heat-friendly for a hot day')
    }
    if (/heavy|fleece|wool|jacket|sweater|boot/.test(text) && !/merino|lightweight/.test(text)) {
      addItemScore(-16, 'Weather penalty: heavy or warm for a hot day')
    }
  } else if (dayLowTemperature(weather) < 62) {
    if (/jacket|sweater|wool|pants|boot/.test(text)) {
      addItemScore(12, 'Weather bonus: useful for a cooler day')
    }
    if (/short sleeve|shorts|linen/.test(text)) {
      addItemScore(-10, 'Weather penalty: light piece on a cooler day')
    }
  }

  if (weather.isRaining || /rain|storm/.test(weather.condition.toLowerCase())) {
    if (isRainFriendly(item)) {
      addItemScore(14, 'Weather bonus: rain-friendly')
    }
    if (/suede|white sneaker|canvas/.test(text)) {
      addItemScore(-8, 'Weather penalty: poor choice for rain risk')
    }
  }

  const styleText = profileStyleSummary(profile).toLowerCase()
  if (styleText) {
    if (styleText.includes('runs hot') && dayHighTemperature(weather) >= 74 && isHeatFriendly(item)) {
      addItemScore(8, 'Profile bonus: user runs hot and this is heat-friendly')
    }
    if (styleText.includes('no shorts for work') && isWorkContext(context) && isShorts(item)) {
      addItemScore(-28, 'Profile penalty: user rule rejects shorts for work')
    }
    if (styleText.includes('no shorts with boots') && (isShorts(item) || isBoots(item))) {
      addItemScore(-4, 'Profile penalty: part of a disliked shorts-with-boots combo')
    }
  }

  if (profile?.temperatureSensitivity === 'runs_hot' && dayHighTemperature(weather) >= 74) {
    if (isHeatFriendly(item)) {
      addItemScore(7, 'Temperature preference bonus: user runs hot')
    }
    if (/jacket|sweater|fleece|heavy/.test(text)) {
      addItemScore(-10, 'Temperature preference penalty: warm layer for user who runs hot')
    }
  }

  if (profile?.temperatureSensitivity === 'runs_cold' && dayLowTemperature(weather) <= 76) {
    if (/pants|sweater|jacket|wool|merino|layer/.test(text)) {
      addItemScore(7, 'Temperature preference bonus: user runs cold')
    }
    if (/shorts|tank|sleeveless/.test(text)) {
      addItemScore(-7, 'Temperature preference penalty: too light for user who runs cold')
    }
  }

  const rotationPenalty = recentWearPenalty(item)
  if (rotationPenalty > 0) {
    addItemScore(-rotationPenalty, 'Rotation penalty: item was worn recently')
  }

  return {
    categoryLabel: categoryLabel(item.category),
    components,
    contributionToOutfit: 0,
    itemID: item.id,
    itemName: item.name,
    rawScore: Math.round(score),
  }
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

function dayHighTemperature(weather: WeatherInput) {
  return Math.max(weather.highTemperatureF ?? weather.temperatureF, weather.temperatureF)
}

function dayLowTemperature(weather: WeatherInput) {
  return Math.min(weather.lowTemperatureF ?? weather.temperatureF, weather.temperatureF)
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

function isInsulatingLayer(item: ClothingItem) {
  return /fleece|heavy|insulated|down|wool sweater|thick|parka/.test(itemText(item))
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
