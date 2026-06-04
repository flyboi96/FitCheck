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
import {
  isDefaultOutfitContext,
  categoryName,
  defaultWeatherInput,
  normalizeOutfitContext,
  outfitContexts,
  weatherSummary,
  type OutfitContext,
  type OutfitRecommendation,
  type OutfitSource,
  type WeatherInput,
} from './outfits'
import type { ClothingCategory, ClothingItem } from './closet'

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

export type Plan = {
  id: string
  name: string
  startDate: string
  endDate: string
  notes: string
  days: PlanDay[]
  itinerary: ItineraryOutfit[]
  packingList: PackingListItem[]
}

export type PlanDraft = Pick<Plan, 'name' | 'startDate' | 'endDate' | 'notes' | 'days'>

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
    cautions: recommendation.cautions,
  }
}

export function buildPackingList(
  itinerary: ItineraryOutfit[],
  closet: ClothingItem[],
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
        packQuantity: packingQuantityFor(item, useCount),
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
  const lines = [`FitCheck Itinerary - ${plan.name}`, `${plan.startDate} to ${plan.endDate}`, '']

  if (plan.notes) {
    lines.push(`Notes: ${plan.notes}`, '')
  }

  plan.itinerary.forEach((outfit) => {
    lines.push(`${outfit.date} - ${outfit.location || 'Location TBD'} - ${outfit.label}`)
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
  const lines = [`FitCheck Packing List - ${plan.name}`, `${plan.startDate} to ${plan.endDate}`, '']
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
    condition: stringValue(data.condition, defaultWeatherInput.condition),
    isRaining: Boolean(data.isRaining),
    humidityPercent: numberValue(data.humidityPercent, defaultWeatherInput.humidityPercent),
    windMph: numberValue(data.windMph, defaultWeatherInput.windMph),
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
    cautions: stringArray(data.cautions),
  }
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

function packingQuantityFor(item: ClothingItem, useCount: number) {
  if (item.category === 'underwear' || item.category === 'socks') {
    return Math.min(item.quantity, useCount)
  }

  if (item.category === 'activewear') {
    return Math.min(item.quantity, Math.max(1, useCount))
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
