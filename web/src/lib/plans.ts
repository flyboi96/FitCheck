import {
  addDoc,
  collection,
  deleteDoc,
  doc,
  onSnapshot,
  serverTimestamp,
  updateDoc,
  type FirestoreError,
  type Unsubscribe,
} from 'firebase/firestore'
import { db } from './firebase'
import { formatDateRangeWithWeekdays, formatDateWithWeekday } from './dateFormatting'
import {
  isDefaultOutfitContext,
  categoryName,
  defaultWeatherInput,
  normalizeOutfitContext,
  outfitContexts,
  weatherSummary,
  type OutfitContext,
  type OutfitRecommendation,
  type OutfitScoreBreakdown,
  type OutfitSource,
  type WeatherInput,
} from './outfits'
import { itemCanBeUsedForOutfits, type ClothingCategory, type ClothingItem } from './closet'

export type PlanOutfitRequest = {
  id: string
  context: OutfitContext
  label: string
}

export type PlanDay = {
  id: string
  date: string
  location: string
  weather: WeatherInput
  requests: PlanOutfitRequest[]
}

export type ItineraryOutfit = {
  id: string
  date: string
  location: string
  context: OutfitContext
  label: string
  weatherSummary: string
  itemIDs: string[]
  itemNames: string[]
  score: number
  scoreLabel: string
  source: OutfitSource
  rationale: string
  reasons: string[]
  scoreBreakdown?: OutfitScoreBreakdown
  cautions: string[]
}

export type PackingListItem = {
  itemID: string
  name: string
  category: ClothingCategory
  categoryLabel: string
  packQuantity: number
  useCount: number
  availableQuantity: number
}

export type PlanLaundrySettings = {
  avoidConsecutiveRepeats: boolean
  maxUsesBeforeLaundry: Record<ClothingCategory, number>
}

export type PlanClosetScope = 'available' | 'entire' | 'selected'

export type PlanPackingSettings = {
  categoryTargets: Record<ClothingCategory, number>
  closetScope: PlanClosetScope
  requiredItemIDs: string[]
  selectedItemIDs: string[]
}

export type Plan = {
  id: string
  name: string
  startDate: string
  endDate: string
  notes: string
  laundrySettings: PlanLaundrySettings
  packingSettings: PlanPackingSettings
  days: PlanDay[]
  itinerary: ItineraryOutfit[]
  packingList: PackingListItem[]
}

export type PlanDraft = Pick<
  Plan,
  'name' | 'startDate' | 'endDate' | 'notes' | 'laundrySettings' | 'packingSettings' | 'days'
>

export type NewPlanDraft = {
  name: string
  startDate: string
  endDate: string
  location: string
  notes: string
}

const defaultContext: OutfitContext = 'casual'
export const MAX_EXPANDED_PLAN_DAYS = 21
const millisecondsPerDay = 24 * 60 * 60 * 1000
const unlimitedLaundryUses = 0

export const defaultPlanLaundrySettings: PlanLaundrySettings = {
  avoidConsecutiveRepeats: true,
  maxUsesBeforeLaundry: {
    shirt: 1,
    blouse: 1,
    pants: 2,
    shorts: 2,
    dress: 1,
    skirt: 2,
    shoes: unlimitedLaundryUses,
    heels: unlimitedLaundryUses,
    flats: unlimitedLaundryUses,
    jacket: unlimitedLaundryUses,
    sweater: 3,
    activewear: 1,
    underwear: 1,
    socks: 1,
    belt: unlimitedLaundryUses,
    watch: unlimitedLaundryUses,
    jewelry: unlimitedLaundryUses,
    accessory: unlimitedLaundryUses,
    bag: unlimitedLaundryUses,
    purse: unlimitedLaundryUses,
    other: 1,
  },
}

export const defaultPlanPackingSettings: PlanPackingSettings = {
  categoryTargets: Object.fromEntries(
    Object.keys(defaultPlanLaundrySettings.maxUsesBeforeLaundry).map((category) => [category, 0]),
  ) as Record<ClothingCategory, number>,
  closetScope: 'available',
  requiredItemIDs: [],
  selectedItemIDs: [],
}

function requireFirestore() {
  if (!db) {
    throw new Error('Firebase is not configured.')
  }

  return db
}

function plansCollection(userId: string) {
  return collection(requireFirestore(), 'users', userId, 'plans')
}

function planDoc(userId: string, planId: string) {
  return doc(requireFirestore(), 'users', userId, 'plans', planId)
}

export function todayISO() {
  const now = new Date()
  const month = `${now.getMonth() + 1}`.padStart(2, '0')
  const day = `${now.getDate()}`.padStart(2, '0')
  return `${now.getFullYear()}-${month}-${day}`
}

export function addDaysISO(date: string, daysToAdd: number) {
  const parsedDate = parseISODateUTC(date)

  if (!parsedDate) {
    return todayISO()
  }

  parsedDate.setUTCDate(parsedDate.getUTCDate() + daysToAdd)
  return formatISODateUTC(parsedDate)
}

export function dateRangeDayCount(startDate: string, endDate: string) {
  const parsedStartDate = parseISODateUTC(startDate)
  const parsedEndDate = parseISODateUTC(endDate)

  if (!parsedStartDate || !parsedEndDate || parsedEndDate < parsedStartDate) {
    return 1
  }

  return Math.floor((parsedEndDate.getTime() - parsedStartDate.getTime()) / millisecondsPerDay) + 1
}

export function defaultNewPlanDraft(): NewPlanDraft {
  const startDate = todayISO()
  return {
    name: 'Upcoming Plan',
    startDate,
    endDate: startDate,
    location: '',
    notes: '',
  }
}

export function createDaysFromRange({
  endDate,
  location,
  startDate,
}: Pick<NewPlanDraft, 'endDate' | 'location' | 'startDate'>): PlanDay[] {
  const days: PlanDay[] = []
  const normalizedStartDate = normalizePlanDate(startDate)
  const normalizedEndDate = normalizePlanDate(endDate, normalizedStartDate)
  const dayCount = Math.min(
    dateRangeDayCount(normalizedStartDate, normalizedEndDate),
    MAX_EXPANDED_PLAN_DAYS,
  )
  let currentDate = normalizedStartDate

  for (let index = 0; index < dayCount; index += 1) {
    days.push(createPlanDay(currentDate, location))
    currentDate = addDaysISO(currentDate, 1)
  }

  return days.length > 0 ? days : [createPlanDay(normalizedStartDate, location)]
}

export function createPlanDay(date: string, location: string): PlanDay {
  return {
    id: crypto.randomUUID(),
    date,
    location,
    weather: {
      ...defaultWeatherInput,
      location,
    },
    requests: [createOutfitRequest(defaultContext)],
  }
}

export function createOutfitRequest(context: OutfitContext): PlanOutfitRequest {
  return {
    id: crypto.randomUUID(),
    context,
    label: outfitContexts.find((option) => option.value === context)?.label ?? context,
  }
}

export function subscribeToPlans(
  userId: string,
  onPlans: (plans: Plan[]) => void,
  onError: (error: FirestoreError) => void,
): Unsubscribe {
  return onSnapshot(
    plansCollection(userId),
    (snapshot) => {
      const plans = snapshot.docs
        .map((planSnapshot) => normalizePlan(planSnapshot.id, planSnapshot.data()))
        .sort((first, second) => first.startDate.localeCompare(second.startDate))

      onPlans(plans)
    },
    onError,
  )
}

export async function createPlan(userId: string, draft: NewPlanDraft) {
  const normalizedDraft = normalizeNewPlanDraft(draft)
  const planRef = await addDoc(plansCollection(userId), {
    ...normalizedDraft,
    days: createDaysFromRange(normalizedDraft).map(serializePlanDay),
    itinerary: [],
    laundrySettings: serializeLaundrySettings(defaultPlanLaundrySettings),
    packingSettings: serializePackingSettings(defaultPlanPackingSettings),
    packingList: [],
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  })
  return planRef.id
}

export async function savePlan(userId: string, planId: string, draft: PlanDraft) {
  await updateDoc(planDoc(userId, planId), {
    name: draft.name.trim() || 'Untitled Plan',
    startDate: draft.startDate,
    endDate: draft.endDate,
    notes: draft.notes.trim(),
    laundrySettings: serializeLaundrySettings(draft.laundrySettings),
    packingSettings: serializePackingSettings(draft.packingSettings),
    days: draft.days.map(serializePlanDay),
    updatedAt: serverTimestamp(),
  })
}

export async function saveGeneratedPlan(
  userId: string,
  planId: string,
  itinerary: ItineraryOutfit[],
  packingList: PackingListItem[],
) {
  await updateDoc(planDoc(userId, planId), {
    itinerary,
    packingList,
    updatedAt: serverTimestamp(),
  })
}

export async function deletePlan(userId: string, planId: string) {
  await deleteDoc(planDoc(userId, planId))
}

export function recommendationToItineraryOutfit({
  day,
  recommendation,
  request,
}: {
  day: PlanDay
  recommendation: OutfitRecommendation
  request: PlanOutfitRequest
}): ItineraryOutfit {
  return {
    id: crypto.randomUUID(),
    date: day.date,
    location: day.location,
    context: request.context,
    label: request.label || contextLabel(request.context),
    weatherSummary: weatherSummary(day.weather),
    itemIDs: recommendation.items.map((item) => item.id),
    itemNames: recommendation.items.map((item) => item.name),
    score: recommendation.score,
    scoreLabel: recommendation.scoreLabel,
    source: recommendation.source,
    rationale: recommendation.rationale,
    reasons: recommendation.reasons,
    scoreBreakdown: recommendation.scoreBreakdown,
    cautions: recommendation.cautions,
  }
}

export function buildPackingList(
  itinerary: ItineraryOutfit[],
  closet: ClothingItem[],
  laundrySettings: PlanLaundrySettings = defaultPlanLaundrySettings,
): PackingListItem[] {
  const usageByItemID = new Map<string, number>()

  itinerary.forEach((outfit) => {
    outfit.itemIDs.forEach((itemID) => {
      usageByItemID.set(itemID, (usageByItemID.get(itemID) ?? 0) + 1)
    })
  })

  return [...usageByItemID.entries()]
    .map(([itemID, useCount]) => {
      const item = closet.find((closetItem) => closetItem.id === itemID)

      if (!item) {
        return null
      }

      return {
        itemID,
        name: item.name,
        category: item.category,
        categoryLabel: categoryName(item.category),
        packQuantity: packingQuantityFor(item, useCount, laundrySettings),
        useCount,
        availableQuantity: item.quantity,
      }
    })
    .filter((item): item is PackingListItem => Boolean(item))
    .sort((first, second) => {
      const categoryComparison = first.categoryLabel.localeCompare(second.categoryLabel)
      return categoryComparison === 0 ? first.name.localeCompare(second.name) : categoryComparison
    })
}

export function itineraryShareText(plan: Plan) {
  const lines = [
    `FitCheck Itinerary - ${plan.name}`,
    formatDateRangeWithWeekdays(plan.startDate, plan.endDate),
    '',
  ]

  if (plan.notes) {
    lines.push(`Notes: ${plan.notes}`, '')
  }

  plan.itinerary.forEach((outfit) => {
    lines.push(
      `${formatDateWithWeekday(outfit.date)} - ${outfit.location || 'Location TBD'} - ${outfit.label}`,
    )
    lines.push(`Score: ${outfit.score}/100 ${outfit.scoreLabel}`)
    outfit.itemNames.forEach((itemName) => lines.push(`- ${itemName}`))
    if (outfit.rationale) {
      lines.push(`Why: ${outfit.rationale}`)
    }
    lines.push('')
  })

  return lines.join('\n').trim()
}

export function packingListShareText(plan: Plan) {
  const lines = [
    `FitCheck Packing List - ${plan.name}`,
    formatDateRangeWithWeekdays(plan.startDate, plan.endDate),
    '',
  ]
  let currentCategory = ''

  plan.packingList.forEach((item) => {
    if (item.categoryLabel !== currentCategory) {
      currentCategory = item.categoryLabel
      lines.push(currentCategory)
    }

    lines.push(
      `- ${item.name}: pack ${item.packQuantity} (used ${item.useCount}x, available ${item.availableQuantity})`,
    )
  })

  return lines.join('\n').trim()
}

export function closetAvailableForPlanRequest({
  includeUnavailableItems = false,
  closet,
  laundrySettings,
  previousDayItemIDs,
  usageByItemID,
}: {
  closet: ClothingItem[]
  includeUnavailableItems?: boolean
  laundrySettings: PlanLaundrySettings
  previousDayItemIDs: Set<string>
  usageByItemID: Map<string, number>
}) {
  return closet.filter((item) => {
    if (!itemCanBeUsedForOutfits(item, includeUnavailableItems)) {
      return false
    }

    if (hasHitLaundryUseLimit(item, usageByItemID.get(item.id) ?? 0, laundrySettings)) {
      return false
    }

    if (
      laundrySettings.avoidConsecutiveRepeats &&
      item.quantity <= 1 &&
      previousDayItemIDs.has(item.id) &&
      maxUsesForCategory(item.category, laundrySettings) > 0
    ) {
      return false
    }

    return true
  })
}

export function closetForPlanPackingSettings(
  closet: ClothingItem[],
  settings: PlanPackingSettings = defaultPlanPackingSettings,
) {
  const selectedItemIDs = new Set(settings.selectedItemIDs)

  if (settings.closetScope === 'selected') {
    return closet.filter((item) => selectedItemIDs.has(item.id) && item.status !== 'archived')
  }

  if (settings.closetScope === 'entire') {
    return closet.filter((item) => item.status !== 'archived')
  }

  return closet.filter((item) => itemCanBeUsedForOutfits(item))
}

function normalizeNewPlanDraft(draft: NewPlanDraft): NewPlanDraft {
  const startDate = normalizePlanDate(draft.startDate)
  const requestedEndDate = normalizePlanDate(draft.endDate, startDate)
  const endDate = dateRangeDayCount(startDate, requestedEndDate) > 1 ? requestedEndDate : startDate

  return {
    name: draft.name.trim() || 'Upcoming Plan',
    startDate,
    endDate,
    location: draft.location.trim(),
    notes: draft.notes.trim(),
  }
}

function serializePlanDay(day: PlanDay) {
  return {
    id: day.id,
    date: day.date,
    location: day.location.trim(),
    weather: {
      ...day.weather,
      location: day.location.trim() || day.weather.location,
    },
    requests: day.requests.map((request) => ({
      id: request.id,
      context: request.context,
      label: request.label.trim() || contextLabel(request.context),
    })),
  }
}

function normalizePlan(id: string, data: Record<string, unknown>): Plan {
  const startDate = normalizePlanDate(stringValue(data.startDate, todayISO()))
  const requestedEndDate = normalizePlanDate(stringValue(data.endDate, startDate), startDate)
  const endDate = dateRangeDayCount(startDate, requestedEndDate) > 1 ? requestedEndDate : startDate

  return {
    id,
    name: stringValue(data.name, 'Untitled Plan'),
    startDate,
    endDate,
    notes: stringValue(data.notes),
    laundrySettings: normalizeLaundrySettings(data.laundrySettings),
    packingSettings: normalizePackingSettings(data.packingSettings),
    days: normalizePlanDays(data.days, startDate),
    itinerary: normalizeItinerary(data.itinerary),
    packingList: normalizePackingList(data.packingList),
  }
}

function normalizePlanDays(value: unknown, startDate: string) {
  if (!Array.isArray(value)) {
    return [createPlanDay(startDate, '')]
  }

  const days = value.map((day) => normalizePlanDay(day)).filter((day): day is PlanDay => Boolean(day))
  return days.length > 0
    ? days.sort((first, second) => first.date.localeCompare(second.date))
    : [createPlanDay(startDate, '')]
}

function normalizePlanDay(value: unknown): PlanDay | null {
  if (!value || typeof value !== 'object') {
    return null
  }

  const data = value as Record<string, unknown>
  const date = normalizePlanDate(stringValue(data.date, todayISO()))
  const location = stringValue(data.location)

  return {
    id: stringValue(data.id, crypto.randomUUID()),
    date,
    location,
    weather: normalizeWeather(data.weather, location),
    requests: normalizeRequests(data.requests),
  }
}

function normalizeWeather(value: unknown, location: string): WeatherInput {
  if (!value || typeof value !== 'object') {
    return { ...defaultWeatherInput, location }
  }

  const data = value as Record<string, unknown>
  return {
    location: stringValue(data.location, location),
    temperatureF: numberValue(data.temperatureF, defaultWeatherInput.temperatureF),
    highTemperatureF: numberValue(
      data.highTemperatureF,
      numberValue(data.temperatureF, defaultWeatherInput.highTemperatureF),
    ),
    lowTemperatureF: numberValue(
      data.lowTemperatureF,
      numberValue(data.temperatureF, defaultWeatherInput.lowTemperatureF),
    ),
    condition: stringValue(data.condition, defaultWeatherInput.condition),
    isRaining: Boolean(data.isRaining),
    humidityPercent: numberValue(data.humidityPercent, defaultWeatherInput.humidityPercent),
    windMph: numberValue(data.windMph, defaultWeatherInput.windMph),
    source: stringValue(data.source),
  }
}

function normalizeRequests(value: unknown): PlanOutfitRequest[] {
  if (!Array.isArray(value) || value.length === 0) {
    return [createOutfitRequest(defaultContext)]
  }

  const requests = value
    .map(normalizeRequest)
    .filter((request): request is PlanOutfitRequest => Boolean(request))

  return requests.length > 0 ? requests : [createOutfitRequest(defaultContext)]
}

function normalizeRequest(value: unknown): PlanOutfitRequest | null {
  if (!value || typeof value !== 'object') {
    return null
  }

  const data = value as Record<string, unknown>
  const context = contextValue(data.context)
  const savedLabel = stringValue(data.label).trim()

  return {
    id: stringValue(data.id, crypto.randomUUID()),
    context,
    label: isDefaultOutfitContext(context) ? contextLabel(context) : savedLabel || contextLabel(context),
  }
}

function normalizeItinerary(value: unknown): ItineraryOutfit[] {
  if (!Array.isArray(value)) {
    return []
  }

  return value.map(normalizeItineraryOutfit).filter((outfit): outfit is ItineraryOutfit => Boolean(outfit))
}

function normalizeItineraryOutfit(value: unknown): ItineraryOutfit | null {
  if (!value || typeof value !== 'object') {
    return null
  }

  const data = value as Record<string, unknown>
  const context = contextValue(data.context)
  const savedLabel = stringValue(data.label).trim()
  const scoreBreakdown = normalizeScoreBreakdown(data.scoreBreakdown)

  return {
    id: stringValue(data.id, crypto.randomUUID()),
    date: stringValue(data.date, todayISO()),
    location: stringValue(data.location),
    context,
    label: isDefaultOutfitContext(context) ? contextLabel(context) : savedLabel || contextLabel(context),
    weatherSummary: stringValue(data.weatherSummary),
    itemIDs: stringArray(data.itemIDs),
    itemNames: stringArray(data.itemNames),
    score: numberValue(data.score, 0),
    scoreLabel: stringValue(data.scoreLabel, 'Unscored'),
    source: data.source === 'ai' ? 'ai' : 'local',
    rationale: stringValue(data.rationale),
    reasons: stringArray(data.reasons),
    ...(scoreBreakdown ? { scoreBreakdown } : {}),
    cautions: stringArray(data.cautions),
  }
}

function normalizeScoreBreakdown(value: unknown): OutfitScoreBreakdown | undefined {
  if (!value || typeof value !== 'object') {
    return undefined
  }

  const data = value as Record<string, unknown>
  const finalScore = numberValue(data.finalScore, 0)
  const rawScore = numberValue(data.rawScore, finalScore)
  const startingScore = numberValue(data.startingScore, 62)

  return {
    finalScore,
    itemBreakdowns: Array.isArray(data.itemBreakdowns)
      ? data.itemBreakdowns
          .map((itemBreakdown) => {
            if (!itemBreakdown || typeof itemBreakdown !== 'object') {
              return null
            }

            const itemData = itemBreakdown as Record<string, unknown>
            return {
              categoryLabel: stringValue(itemData.categoryLabel, 'Item'),
              components: normalizeScoreComponents(itemData.components),
              contributionToOutfit: numberValue(itemData.contributionToOutfit, 0),
              itemID: stringValue(itemData.itemID),
              itemName: stringValue(itemData.itemName, 'Item'),
              rawScore: numberValue(itemData.rawScore, 0),
            }
          })
          .filter((itemBreakdown): itemBreakdown is OutfitScoreBreakdown['itemBreakdowns'][number] =>
            Boolean(itemBreakdown),
          )
      : [],
    outfitComponents: normalizeScoreComponents(data.outfitComponents),
    rawScore,
    startingScore,
  }
}

function normalizeScoreComponents(value: unknown) {
  if (!Array.isArray(value)) {
    return []
  }

  return value
    .map((component) => {
      if (!component || typeof component !== 'object') {
        return null
      }

      const data = component as Record<string, unknown>
      const kind = stringValue(data.kind, 'bonus')
      return {
        delta: numberValue(data.delta, 0),
        kind:
          kind === 'base' || kind === 'bonus' || kind === 'item' || kind === 'penalty'
            ? kind
            : 'bonus',
        label: stringValue(data.label, 'Score adjustment'),
        scoreAfter: numberValue(data.scoreAfter, 0),
      }
    })
    .filter((component): component is OutfitScoreBreakdown['outfitComponents'][number] =>
      Boolean(component),
    )
}

function normalizePackingList(value: unknown): PackingListItem[] {
  if (!Array.isArray(value)) {
    return []
  }

  return value
    .map((item) => {
      if (!item || typeof item !== 'object') {
        return null
      }

      const data = item as Record<string, unknown>
      const category = stringValue(data.category, 'other') as ClothingCategory

      return {
        itemID: stringValue(data.itemID),
        name: stringValue(data.name),
        category,
        categoryLabel: stringValue(data.categoryLabel, categoryName(category)),
        packQuantity: numberValue(data.packQuantity, 1),
        useCount: numberValue(data.useCount, 1),
        availableQuantity: numberValue(data.availableQuantity, 1),
      }
    })
    .filter((item): item is PackingListItem => Boolean(item))
}

function packingQuantityFor(
  item: ClothingItem,
  useCount: number,
  laundrySettings: PlanLaundrySettings,
) {
  const maxUses = maxUsesForCategory(item.category, laundrySettings)

  if (maxUses > 0) {
    return Math.min(item.quantity, Math.max(1, Math.ceil(useCount / maxUses)))
  }

  if (
    item.category === 'belt' ||
    item.category === 'watch' ||
    item.category === 'jewelry' ||
    item.category === 'accessory' ||
    item.category === 'bag' ||
    item.category === 'purse' ||
    item.category === 'jacket' ||
    item.category === 'shoes' ||
    item.category === 'heels' ||
    item.category === 'flats'
  ) {
    return Math.min(item.quantity, 1)
  }

  return Math.min(item.quantity, Math.max(1, Math.min(useCount, 3)))
}

function hasHitLaundryUseLimit(
  item: ClothingItem,
  useCount: number,
  laundrySettings: PlanLaundrySettings,
) {
  const maxUses = maxUsesForCategory(item.category, laundrySettings)
  return maxUses > 0 && useCount >= maxUses * Math.max(1, item.quantity)
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

function serializeLaundrySettings(settings: PlanLaundrySettings) {
  return {
    avoidConsecutiveRepeats: Boolean(settings.avoidConsecutiveRepeats),
    maxUsesBeforeLaundry: Object.fromEntries(
      Object.entries(defaultPlanLaundrySettings.maxUsesBeforeLaundry).map(([category, fallback]) => [
        category,
        Math.max(
          0,
          Math.floor(
            settings.maxUsesBeforeLaundry[category as ClothingCategory] ?? Number(fallback),
          ),
        ),
      ]),
    ),
  }
}

function serializePackingSettings(settings: PlanPackingSettings = defaultPlanPackingSettings) {
  return {
    categoryTargets: Object.fromEntries(
      Object.entries(defaultPlanPackingSettings.categoryTargets).map(([category]) => [
        category,
        Math.max(
          0,
          Math.floor(settings.categoryTargets[category as ClothingCategory] ?? 0),
        ),
      ]),
    ),
    closetScope:
      settings.closetScope === 'entire' || settings.closetScope === 'selected'
        ? settings.closetScope
        : 'available',
    requiredItemIDs: uniqueStrings(settings.requiredItemIDs),
    selectedItemIDs: uniqueStrings(settings.selectedItemIDs),
  }
}

function normalizeLaundrySettings(value: unknown): PlanLaundrySettings {
  if (!value || typeof value !== 'object') {
    return defaultPlanLaundrySettings
  }

  const data = value as Record<string, unknown>
  const maxUsesData =
    data.maxUsesBeforeLaundry && typeof data.maxUsesBeforeLaundry === 'object'
      ? (data.maxUsesBeforeLaundry as Record<string, unknown>)
      : {}

  return {
    avoidConsecutiveRepeats:
      typeof data.avoidConsecutiveRepeats === 'boolean'
        ? data.avoidConsecutiveRepeats
        : defaultPlanLaundrySettings.avoidConsecutiveRepeats,
    maxUsesBeforeLaundry: Object.fromEntries(
      Object.entries(defaultPlanLaundrySettings.maxUsesBeforeLaundry).map(([category, fallback]) => [
        category,
        Math.max(0, Math.floor(numberValue(maxUsesData[category], Number(fallback)))),
      ]),
    ) as Record<ClothingCategory, number>,
  }
}

function normalizePackingSettings(value: unknown): PlanPackingSettings {
  if (!value || typeof value !== 'object') {
    return defaultPlanPackingSettings
  }

  const data = value as Record<string, unknown>
  const categoryTargetsData =
    data.categoryTargets && typeof data.categoryTargets === 'object'
      ? (data.categoryTargets as Record<string, unknown>)
      : {}
  const closetScope = stringValue(data.closetScope, 'available')

  return {
    categoryTargets: Object.fromEntries(
      Object.entries(defaultPlanPackingSettings.categoryTargets).map(([category]) => [
        category,
        Math.max(0, Math.floor(numberValue(categoryTargetsData[category], 0))),
      ]),
    ) as Record<ClothingCategory, number>,
    closetScope:
      closetScope === 'entire' || closetScope === 'selected' ? closetScope : 'available',
    requiredItemIDs: uniqueStrings(stringArray(data.requiredItemIDs)),
    selectedItemIDs: uniqueStrings(stringArray(data.selectedItemIDs)),
  }
}

function uniqueStrings(values: string[]) {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))]
}

function contextValue(value: unknown): OutfitContext {
  return normalizeOutfitContext(value)
}

function contextLabel(context: OutfitContext) {
  return outfitContexts.find((option) => option.value === context)?.label ?? context
}

function stringValue(value: unknown, fallback = '') {
  return typeof value === 'string' ? value : fallback
}

function numberValue(value: unknown, fallback: number) {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback
}

function normalizePlanDate(date: string, fallback = todayISO()) {
  return parseISODateUTC(date) ? date : fallback
}

function parseISODateUTC(date: string) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date)

  if (!match) {
    return null
  }

  const year = Number(match[1])
  const month = Number(match[2])
  const day = Number(match[3])
  const parsedDate = new Date(Date.UTC(year, month - 1, day))

  if (
    parsedDate.getUTCFullYear() !== year ||
    parsedDate.getUTCMonth() !== month - 1 ||
    parsedDate.getUTCDate() !== day
  ) {
    return null
  }

  return parsedDate
}

function formatISODateUTC(date: Date) {
  return date.toISOString().slice(0, 10)
}

function stringArray(value: unknown) {
  return Array.isArray(value) ? value.map(String) : []
}
