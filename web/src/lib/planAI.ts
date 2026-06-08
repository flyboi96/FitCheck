import { categoryLabel, type ClothingCategory, type ClothingItem } from './closet'
import { contextOptionsFromSettings, contextStylesPrompt, loadContextStyles } from './contextStyles'
import {
  loadRecentFeedback,
  scoreCustomOutfit,
  validateOutfitRecommendation,
  weatherSummary,
  type OutfitContextOption,
} from './outfits'
import type { UserProfile } from './profile'
import { profileStyleSummary } from './profile'
import {
  defaultPlanLaundrySettings,
  closetForPlanPackingSettings,
  recommendationToItineraryOutfit,
  type ItineraryOutfit,
  type PlanDraft,
  type PlanLaundrySettings,
} from './plans'
import { getAIProxySettings } from './settings'

type AIPlanOutfit = {
  cautions: string[]
  itemIDs: string[]
  rationale: string
  requestID: string
}

type AIPlanResponse = {
  outfits: AIPlanOutfit[]
  overallRationale: string
  validationIssues: string[]
  warnings: string[]
}

export type AIPlanItineraryResult = {
  attempts: number
  itinerary: ItineraryOutfit[]
  warnings: string[]
}

export async function generateAIPlanItinerary({
  closet,
  draft,
  profile,
  userId,
}: {
  closet: ClothingItem[]
  draft: PlanDraft
  profile: UserProfile | null
  userId: string
}): Promise<AIPlanItineraryResult> {
  const activeCloset = closetForPlanPackingSettings(closet, draft.packingSettings)

  if (activeCloset.length === 0) {
    throw new Error('No closet items match the plan constraints.')
  }

  const settings = getAIProxySettings()
  const baseURL = settings.proxyUrl.trim().replace(/\/+$/, '')

  if (!baseURL) {
    throw new Error('AI proxy URL is not configured in More.')
  }

  const contextStyles = await loadContextStyles(userId)
  const contextOptions = contextOptionsFromSettings(contextStyles)
  const recentFeedback = await loadRecentFeedback(userId)
  let repairInstruction = ''
  let previousOutfits: AIPlanOutfit[] = []
  let lastBlockers: string[] = []

  for (let attempt = 1; attempt <= 2; attempt += 1) {
    const response = await requestAIPlanItinerary({
      activeCloset,
      baseURL,
      contextDefinitions: contextStylesPrompt(contextStyles),
      contextOptions,
      draft,
      previousOutfits,
      profile,
      proxyToken: settings.proxyToken,
      recentFeedback,
      repairInstruction,
    })
    const evaluated = evaluateAIPlanResponse({
      activeCloset,
      contextOptions,
      draft,
      profile,
      response,
    })

    if (evaluated.blockers.length === 0) {
      return {
        attempts: attempt,
        itinerary: evaluated.itinerary,
        warnings: [...response.warnings, ...evaluated.warnings],
      }
    }

    lastBlockers = evaluated.blockers
    previousOutfits = response.outfits
    repairInstruction = [
      'FitCheck rejected the previous itinerary. Repair every listed issue and return the full itinerary again.',
      ...lastBlockers.slice(0, 18),
    ].join('\n')
  }

  throw new Error(
    [
      'AI itinerary did not pass FitCheck quality validation.',
      'No bad itinerary was saved.',
      ...lastBlockers.slice(0, 8),
    ].join('\n'),
  )
}

async function requestAIPlanItinerary({
  activeCloset,
  baseURL,
  contextDefinitions,
  contextOptions,
  draft,
  previousOutfits,
  profile,
  proxyToken,
  recentFeedback,
  repairInstruction,
}: {
  activeCloset: ClothingItem[]
  baseURL: string
  contextDefinitions: string
  contextOptions: OutfitContextOption[]
  draft: PlanDraft
  previousOutfits: AIPlanOutfit[]
  profile: UserProfile | null
  proxyToken: string
  recentFeedback: string[]
  repairInstruction: string
}) {
  const response = await fetch(`${baseURL}/plan-itinerary`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(proxyToken.trim() ? { 'X-FitCheck-Token': proxyToken.trim() } : {}),
    },
    body: JSON.stringify({
      closet: activeCloset.map((item) => ({
        id: item.id,
        name: item.name,
        brand: item.brand,
        category: item.category,
        color: item.color,
        material: item.material,
        quantity: item.quantity,
        pattern: item.pattern,
        notes: item.notes,
        wearCount: item.wearCount,
        wearsSinceClean: item.wearsSinceClean,
        lastWornAt: item.lastWornAt,
        status: item.status,
      })),
      contextDefinitions,
      days: draft.days.map((day) => ({
        id: day.id,
        date: day.date,
        location: day.location,
        weather: day.weather,
        weatherSummary: weatherSummary({
          ...day.weather,
          location: day.location || day.weather.location,
        }),
        requests: day.requests.map((request) => {
          const context = contextOptions.find((option) => option.value === request.context)
          return {
            id: request.id,
            context: request.context,
            contextDefinition: context?.description ?? '',
            label: request.label || context?.label || request.context,
          }
        }),
      })),
      plan: {
        endDate: draft.endDate,
        laundrySettings: draft.laundrySettings,
        packingSettings: draft.packingSettings,
        name: draft.name,
        notes: draft.notes,
        startDate: draft.startDate,
      },
      previousOutfits,
      recentFeedback,
      repairInstruction,
      styleDescription: [
        profileStyleSummary(profile),
        'Context style definitions:',
        contextDefinitions,
      ]
        .filter(Boolean)
        .join('\n\n'),
    }),
  })
  const data = await response.json().catch(() => ({}))

  if (!response.ok) {
    throw new Error(typeof data.error === 'string' ? data.error : 'AI plan itinerary request failed.')
  }

  return normalizeAIPlanResponse(data)
}

function evaluateAIPlanResponse({
  activeCloset,
  contextOptions,
  draft,
  profile,
  response,
}: {
  activeCloset: ClothingItem[]
  contextOptions: OutfitContextOption[]
  draft: PlanDraft
  profile: UserProfile | null
  response: AIPlanResponse
}) {
  const outfitByRequestID = new Map(response.outfits.map((outfit) => [outfit.requestID, outfit]))
  const blockers: string[] = [...response.validationIssues]
  const warnings: string[] = []
  const itinerary: ItineraryOutfit[] = []
  const usedItemIDs = new Set<string>()
  const usageByItemID = new Map<string, number>()
  let currentDate = ''
  let previousDayItemIDs = new Set<string>()
  let currentDayItemIDs = new Set<string>()

  for (const day of draft.days) {
    if (day.date !== currentDate) {
      if (currentDate) {
        previousDayItemIDs = currentDayItemIDs
      }
      currentDate = day.date
      currentDayItemIDs = new Set()
    }

    for (const request of day.requests) {
      const aiOutfit = outfitByRequestID.get(request.id)

      if (!aiOutfit) {
        blockers.push(`${day.date} ${request.label}: AI did not return an outfit.`)
        continue
      }

      const selectedItems = aiOutfit.itemIDs
        .map((itemID) => activeCloset.find((item) => item.id === itemID))
        .filter((item): item is ClothingItem => Boolean(item))

      if (selectedItems.length === 0) {
        blockers.push(`${day.date} ${request.label}: AI returned no active closet items.`)
        continue
      }

      const weather = {
        ...day.weather,
        location: day.location || day.weather.location,
      }
      const scored = scoreCustomOutfit({
        context: request.context,
        items: selectedItems,
        profile,
        source: 'ai',
        weather,
      })
      const qualityGate = validateOutfitRecommendation({
        context: request.context,
        profile,
        recommendation: scored,
        weather,
      })
      const reuseBlockers = validatePlanReuse({
        currentDayItemIDs,
        dayDate: day.date,
        items: selectedItems,
        laundrySettings: draft.laundrySettings,
        previousDayItemIDs,
        requestLabel: request.label,
        usageByItemID,
      })

      blockers.push(
        ...qualityGate.blockers.map((blocker) => `${day.date} ${request.label}: ${blocker}`),
        ...reuseBlockers,
      )
      warnings.push(...qualityGate.warnings.map((warning) => `${day.date} ${request.label}: ${warning}`))

      selectedItems.forEach((item) => {
        usedItemIDs.add(item.id)
        usageByItemID.set(item.id, (usageByItemID.get(item.id) ?? 0) + 1)
        currentDayItemIDs.add(item.id)
      })

      const context = contextOptions.find((option) => option.value === request.context)
      const recommendation = {
        ...scored,
        cautions: [
          ...aiOutfit.cautions,
          ...qualityGate.warnings,
          ...scored.cautions,
        ].filter(Boolean),
        rationale:
          aiOutfit.rationale ||
          `AI planned this ${request.label || context?.label || 'outfit'} as part of the whole itinerary.`,
        reasons: [
          'AI planned this as part of the full itinerary, not as an isolated outfit.',
          ...scored.reasons,
        ].slice(0, 7),
      }

      itinerary.push(
        recommendationToItineraryOutfit({
          day,
          recommendation,
          request: {
            ...request,
            label: request.label || context?.label || request.context,
          },
        }),
      )
    }
  }

  blockers.push(...validateRequiredItems(activeCloset, draft.packingSettings.requiredItemIDs, usedItemIDs))
  blockers.push(...validateCategoryTargets(activeCloset, draft.packingSettings.categoryTargets, usedItemIDs))

  return {
    blockers: [...new Set(blockers)],
    itinerary,
    warnings: [...new Set(warnings)],
  }
}

function validateRequiredItems(
  closet: ClothingItem[],
  requiredItemIDs: string[],
  usedItemIDs: Set<string>,
) {
  const blockers: string[] = []

  requiredItemIDs.forEach((itemID) => {
    const item = closet.find((closetItem) => closetItem.id === itemID)

    if (!item) {
      blockers.push('A required item is outside the current planning closet.')
      return
    }

    if (!usedItemIDs.has(itemID)) {
      blockers.push(`Required item was not used: ${item.name}.`)
    }
  })

  return blockers
}

function validateCategoryTargets(
  closet: ClothingItem[],
  categoryTargets: Record<ClothingCategory, number>,
  usedItemIDs: Set<string>,
) {
  const blockers: string[] = []

  Object.entries(categoryTargets).forEach(([category, target]) => {
    const normalizedTarget = Math.max(0, Math.floor(Number(target)))

    if (normalizedTarget === 0) {
      return
    }

    const availableCount = closet.filter((item) => item.category === category).length
    const usedCount = closet.filter(
      (item) => item.category === category && usedItemIDs.has(item.id),
    ).length
    const label = categoryLabel(category as ClothingCategory)

    if (availableCount < normalizedTarget) {
      blockers.push(`Target asks for ${normalizedTarget} ${label}, but only ${availableCount} are in scope.`)
      return
    }

    if (usedCount !== normalizedTarget) {
      blockers.push(`Target asks for ${normalizedTarget} ${label}; itinerary used ${usedCount}.`)
    }
  })

  return blockers
}

function validatePlanReuse({
  currentDayItemIDs,
  dayDate,
  items,
  laundrySettings,
  previousDayItemIDs,
  requestLabel,
  usageByItemID,
}: {
  currentDayItemIDs: Set<string>
  dayDate: string
  items: ClothingItem[]
  laundrySettings: PlanLaundrySettings
  previousDayItemIDs: Set<string>
  requestLabel: string
  usageByItemID: Map<string, number>
}) {
  const blockers: string[] = []

  items.forEach((item) => {
    const maxUses = maxUsesForCategory(item.category, laundrySettings)
    const currentUseCount = usageByItemID.get(item.id) ?? 0

    if (maxUses > 0 && currentUseCount >= maxUses * Math.max(1, item.quantity)) {
      blockers.push(
        `${dayDate} ${requestLabel}: ${item.name} exceeds the max-use-before-laundry rule.`,
      )
    }

    if (
      laundrySettings.avoidConsecutiveRepeats &&
      maxUses > 0 &&
      item.quantity <= 1 &&
      previousDayItemIDs.has(item.id) &&
      !currentDayItemIDs.has(item.id)
    ) {
      blockers.push(`${dayDate} ${requestLabel}: ${item.name} repeats on consecutive days.`)
    }
  })

  return blockers
}

function maxUsesForCategory(category: ClothingCategory, laundrySettings: PlanLaundrySettings) {
  return Math.max(
    0,
    Math.floor(
      laundrySettings.maxUsesBeforeLaundry[category] ??
        defaultPlanLaundrySettings.maxUsesBeforeLaundry[category] ??
        1,
    ),
  )
}

function normalizeAIPlanResponse(value: unknown): AIPlanResponse {
  if (!value || typeof value !== 'object') {
    return {
      outfits: [],
      overallRationale: '',
      validationIssues: ['AI returned an unreadable itinerary response.'],
      warnings: [],
    }
  }

  const data = value as Record<string, unknown>
  return {
    outfits: Array.isArray(data.outfits)
      ? data.outfits
          .map(normalizeAIPlanOutfit)
          .filter((outfit): outfit is AIPlanOutfit => Boolean(outfit))
      : [],
    overallRationale: stringValue(data.overallRationale),
    validationIssues: stringArray(data.validationIssues),
    warnings: stringArray(data.warnings),
  }
}

function normalizeAIPlanOutfit(value: unknown): AIPlanOutfit | null {
  if (!value || typeof value !== 'object') {
    return null
  }

  const data = value as Record<string, unknown>
  const requestID = stringValue(data.requestID)

  if (!requestID) {
    return null
  }

  return {
    cautions: stringArray(data.cautions),
    itemIDs: stringArray(data.itemIDs),
    rationale: stringValue(data.rationale),
    requestID,
  }
}

function stringValue(value: unknown) {
  return typeof value === 'string' ? value : ''
}

function stringArray(value: unknown) {
  return Array.isArray(value) ? value.map(String).filter(Boolean) : []
}
