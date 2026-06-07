import {
  doc,
  onSnapshot,
  serverTimestamp,
  setDoc,
  type FirestoreError,
  type Unsubscribe,
} from 'firebase/firestore'
import { db } from './firebase'
import {
  normalizeOutfitContext,
  weatherSummary,
  type OutfitContext,
  type OutfitRecommendation,
  type OutfitSource,
  type WeatherInput,
} from './outfits'

export type DailyOutfitStatus = 'planned' | 'wearing'

export type DailyOutfit = {
  id: string
  context: OutfitContext
  contextLabel: string
  date: string
  itemIDs: string[]
  itemNames: string[]
  rationale: string
  score: number
  scoreLabel: string
  source: OutfitSource
  status: DailyOutfitStatus
  weatherSummary: string
}

function requireFirestore() {
  if (!db) {
    throw new Error('Firebase is not configured.')
  }

  return db
}

function dailyOutfitDoc(userId: string, date: string) {
  return doc(requireFirestore(), 'users', userId, 'dailyOutfits', date)
}

export function subscribeToDailyOutfit(
  userId: string,
  date: string,
  onOutfit: (outfit: DailyOutfit | null) => void,
  onError: (error: FirestoreError) => void,
): Unsubscribe {
  return onSnapshot(
    dailyOutfitDoc(userId, date),
    (snapshot) => {
      onOutfit(snapshot.exists() ? normalizeDailyOutfit(snapshot.id, snapshot.data()) : null)
    },
    onError,
  )
}

export async function saveDailyOutfit({
  context,
  contextLabel,
  date,
  recommendation,
  status,
  userId,
  weather,
}: {
  context: OutfitContext
  contextLabel: string
  date: string
  recommendation: OutfitRecommendation
  status: DailyOutfitStatus
  userId: string
  weather: WeatherInput
}) {
  await setDoc(
    dailyOutfitDoc(userId, date),
    {
      context,
      contextLabel,
      date,
      itemIDs: recommendation.items.map((item) => item.id),
      itemNames: recommendation.items.map((item) => item.name),
      rationale: recommendation.rationale,
      score: recommendation.score,
      scoreLabel: recommendation.scoreLabel,
      source: recommendation.source,
      status,
      weatherSummary: weatherSummary(weather),
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  )
}

function normalizeDailyOutfit(id: string, data: Record<string, unknown>): DailyOutfit {
  return {
    id,
    context: normalizeOutfitContext(data.context),
    contextLabel: stringValue(data.contextLabel, 'Outfit'),
    date: stringValue(data.date, id),
    itemIDs: stringArrayValue(data.itemIDs),
    itemNames: stringArrayValue(data.itemNames),
    rationale: stringValue(data.rationale),
    score: numberValue(data.score),
    scoreLabel: stringValue(data.scoreLabel),
    source: data.source === 'ai' ? 'ai' : 'local',
    status: data.status === 'wearing' ? 'wearing' : 'planned',
    weatherSummary: stringValue(data.weatherSummary),
  }
}

function stringValue(value: unknown, fallback = '') {
  return typeof value === 'string' ? value : fallback
}

function numberValue(value: unknown, fallback = 0) {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback
}

function stringArrayValue(value: unknown) {
  return Array.isArray(value) ? value.map(String).filter(Boolean) : []
}
