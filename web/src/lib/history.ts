import {
  collection,
  doc,
  getDocs,
  onSnapshot,
  query,
  serverTimestamp,
  where,
  writeBatch,
  type FirestoreError,
  type Unsubscribe,
} from 'firebase/firestore'
import { formatDateTimeWithWeekday } from './dateFormatting'
import { db } from './firebase'
import type { ClothingItem } from './closet'
import {
  isDefaultOutfitContext,
  normalizeOutfitContext,
  outfitContexts,
  weatherSummary,
  type OutfitContext,
  type OutfitRecommendation,
  type WeatherInput,
} from './outfits'

export type LoggedOutfit = {
  id: string
  name: string
  context: OutfitContext
  contextLabel: string
  wornAt: string
  weatherSummary: string
  itemIDs: string[]
  itemNames: string[]
  score: number
  scoreLabel: string
  source: string
  rationale: string
  note: string
}

export type WearLog = {
  id: string
  outfitID: string
  outfitName: string
  itemID: string
  itemName: string
  category: string
  wornAt: string
  context: OutfitContext
  note: string
}

function requireFirestore() {
  if (!db) {
    throw new Error('Firebase is not configured.')
  }

  return db
}

function outfitsCollection(userId: string) {
  return collection(requireFirestore(), 'users', userId, 'outfits')
}

function outfitDoc(userId: string, outfitId: string) {
  return doc(requireFirestore(), 'users', userId, 'outfits', outfitId)
}

function wearLogsCollection(userId: string) {
  return collection(requireFirestore(), 'users', userId, 'wearLogs')
}

export function subscribeToOutfitHistory(
  userId: string,
  onHistory: (outfits: LoggedOutfit[]) => void,
  onError: (error: FirestoreError) => void,
): Unsubscribe {
  return onSnapshot(
    outfitsCollection(userId),
    (snapshot) => {
      const outfits = snapshot.docs
        .map((outfitSnapshot) => normalizeLoggedOutfit(outfitSnapshot.id, outfitSnapshot.data()))
        .sort((first, second) => second.wornAt.localeCompare(first.wornAt))

      onHistory(outfits)
    },
    onError,
  )
}

export function subscribeToWearLogs(
  userId: string,
  onLogs: (logs: WearLog[]) => void,
  onError: (error: FirestoreError) => void,
): Unsubscribe {
  return onSnapshot(
    wearLogsCollection(userId),
    (snapshot) => {
      const logs = snapshot.docs
        .map((logSnapshot) => normalizeWearLog(logSnapshot.id, logSnapshot.data()))
        .sort((first, second) => second.wornAt.localeCompare(first.wornAt))

      onLogs(logs)
    },
    onError,
  )
}

export async function logOutfitWear({
  context,
  contextLabel,
  note,
  recommendation,
  userId,
  weather,
}: {
  context: OutfitContext
  contextLabel: string
  note: string
  recommendation: OutfitRecommendation
  userId: string
  weather: WeatherInput
}) {
  const wornAt = new Date().toISOString()
  const outfitRef = doc(outfitsCollection(userId))
  const outfitName = `${contextLabel} Outfit`
  const trimmedNote = note.trim()

  const batch = writeBatch(requireFirestore())
  batch.set(outfitRef, {
    name: outfitName,
    context,
    contextLabel,
    wornAt,
    weatherSummary: weatherSummary(weather),
    itemIDs: recommendation.items.map((item) => item.id),
    itemNames: recommendation.items.map((item) => item.name),
    score: recommendation.score,
    scoreLabel: recommendation.scoreLabel,
    source: recommendation.source,
    rationale: recommendation.rationale,
    note: trimmedNote,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  })

  for (const item of recommendation.items) {
    batch.set(doc(wearLogsCollection(userId)), {
      outfitID: outfitRef.id,
      outfitName,
      itemID: item.id,
      itemName: item.name,
      category: item.category,
      wornAt,
      context,
      note: trimmedNote,
      createdAt: serverTimestamp(),
    })
  }

  await batch.commit()
  await recalculateWearStats(userId)
}

export async function deleteLoggedOutfit(userId: string, outfit: LoggedOutfit) {
  const matchingLogs = await getDocs(
    query(wearLogsCollection(userId), where('outfitID', '==', outfit.id)),
  )
  const batch = writeBatch(requireFirestore())

  batch.delete(outfitDoc(userId, outfit.id))
  matchingLogs.docs.forEach((logSnapshot) => batch.delete(logSnapshot.ref))

  await batch.commit()
  await recalculateWearStats(userId)
}

export async function clearOutfitHistory(userId: string) {
  const [outfits, wearLogs] = await Promise.all([
    getDocs(outfitsCollection(userId)),
    getDocs(wearLogsCollection(userId)),
  ])
  const batch = writeBatch(requireFirestore())

  outfits.docs.forEach((outfitSnapshot) => batch.delete(outfitSnapshot.ref))
  wearLogs.docs.forEach((logSnapshot) => batch.delete(logSnapshot.ref))

  await batch.commit()
  await recalculateWearStats(userId)
}

async function recalculateWearStats(userId: string) {
  const [wearLogs, clothingItems] = await Promise.all([
    getDocs(wearLogsCollection(userId)),
    getDocs(collection(requireFirestore(), 'users', userId, 'clothingItems')),
  ])
  const logsByItem = new Map<string, WearLog[]>()

  wearLogs.docs.forEach((logSnapshot) => {
    const log = normalizeWearLog(logSnapshot.id, logSnapshot.data())
    const logs = logsByItem.get(log.itemID) ?? []
    logsByItem.set(log.itemID, [...logs, log])
  })

  const batch = writeBatch(requireFirestore())
  clothingItems.docs.forEach((itemSnapshot) => {
    const itemLogs = logsByItem.get(itemSnapshot.id) ?? []
    const lastCleanedAt = stringValue(itemSnapshot.data().lastCleanedAt)
    const lastWornAt = itemLogs.reduce(
      (latest, log) => (log.wornAt > latest ? log.wornAt : latest),
      '',
    )
    const wearsSinceClean = lastCleanedAt
      ? itemLogs.filter((log) => log.wornAt > lastCleanedAt).length
      : itemLogs.length

    batch.update(itemSnapshot.ref, {
      wearCount: itemLogs.length,
      lastWornAt,
      wearsSinceClean,
      updatedAt: serverTimestamp(),
    })
  })

  await batch.commit()
}

function normalizeLoggedOutfit(id: string, data: Record<string, unknown>): LoggedOutfit {
  const context = outfitContextValue(data.context)
  const savedLabel = stringValue(data.contextLabel).trim()

  return {
    id,
    name: stringValue(data.name, 'Outfit'),
    context,
    contextLabel: isDefaultOutfitContext(context) ? contextLabel(context) : savedLabel || contextLabel(context),
    wornAt: dateValue(data.wornAt),
    weatherSummary: stringValue(data.weatherSummary),
    itemIDs: stringArrayValue(data.itemIDs),
    itemNames: stringArrayValue(data.itemNames),
    score: numberValue(data.score),
    scoreLabel: stringValue(data.scoreLabel),
    source: stringValue(data.source),
    rationale: stringValue(data.rationale),
    note: stringValue(data.note),
  }
}

function normalizeWearLog(id: string, data: Record<string, unknown>): WearLog {
  return {
    id,
    outfitID: stringValue(data.outfitID),
    outfitName: stringValue(data.outfitName, 'Outfit'),
    itemID: stringValue(data.itemID),
    itemName: stringValue(data.itemName, 'Unknown item'),
    category: stringValue(data.category),
    wornAt: dateValue(data.wornAt),
    context: outfitContextValue(data.context),
    note: stringValue(data.note),
  }
}

export function wearCountLabel(item: ClothingItem) {
  const lastWorn = item.lastWornAt ? `Last worn ${formatShortDate(item.lastWornAt)}` : 'Never worn'
  const cleanCycle = `${item.wearsSinceClean} since clean`
  return `${item.wearCount} wear${item.wearCount === 1 ? '' : 's'} - ${cleanCycle} - ${lastWorn}`
}

export function formatShortDate(value: string) {
  if (!value) {
    return 'Never'
  }

  return formatDateTimeWithWeekday(value)
}

function stringValue(value: unknown, fallback = '') {
  return typeof value === 'string' ? value : fallback
}

function numberValue(value: unknown, fallback = 0) {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback
}

function stringArrayValue(value: unknown) {
  return Array.isArray(value) ? value.map(String) : []
}

function dateValue(value: unknown) {
  if (typeof value === 'string') {
    return value
  }

  const timestamp = value as { toDate?: () => Date } | undefined
  return timestamp?.toDate?.().toISOString() ?? ''
}

function outfitContextValue(value: unknown): OutfitContext {
  return normalizeOutfitContext(value)
}

function contextLabel(context: OutfitContext) {
  return outfitContexts.find((option) => option.value === context)?.label ?? 'Outfit'
}
