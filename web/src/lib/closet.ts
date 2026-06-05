import {
  addDoc,
  collection,
  deleteDoc,
  doc,
  getDocs,
  onSnapshot,
  serverTimestamp,
  updateDoc,
  writeBatch,
  type FirestoreError,
  type Unsubscribe,
} from 'firebase/firestore'
import { db } from './firebase'
import type { WearerProfile } from './profile'

export type ClothingCategory =
  | 'shirt'
  | 'blouse'
  | 'pants'
  | 'shorts'
  | 'dress'
  | 'skirt'
  | 'shoes'
  | 'heels'
  | 'flats'
  | 'jacket'
  | 'sweater'
  | 'activewear'
  | 'underwear'
  | 'socks'
  | 'belt'
  | 'watch'
  | 'jewelry'
  | 'accessory'
  | 'bag'
  | 'purse'
  | 'other'

export type ClothingStatus = 'active' | 'archived' | 'laundry' | 'unavailable'

export type ClothingItem = {
  id: string
  name: string
  brand: string
  category: ClothingCategory
  quantity: number
  color: string
  material: string
  pattern: string
  notes: string
  status: ClothingStatus
  wearCount: number
  lastWornAt: string
}

export type ClothingItemDraft = Omit<ClothingItem, 'id' | 'wearCount' | 'lastWornAt'>

export const clothingCategories: Array<{
  value: ClothingCategory
  label: string
  femaleFocused?: boolean
}> = [
  { value: 'shirt', label: 'Shirt' },
  { value: 'blouse', label: 'Blouse', femaleFocused: true },
  { value: 'pants', label: 'Pants' },
  { value: 'shorts', label: 'Shorts' },
  { value: 'dress', label: 'Dress', femaleFocused: true },
  { value: 'skirt', label: 'Skirt', femaleFocused: true },
  { value: 'shoes', label: 'Shoes' },
  { value: 'heels', label: 'Heels', femaleFocused: true },
  { value: 'flats', label: 'Flats', femaleFocused: true },
  { value: 'jacket', label: 'Jacket' },
  { value: 'sweater', label: 'Sweater' },
  { value: 'activewear', label: 'Exercise Clothes' },
  { value: 'underwear', label: 'Underwear' },
  { value: 'socks', label: 'Socks' },
  { value: 'belt', label: 'Belt' },
  { value: 'watch', label: 'Watch' },
  { value: 'jewelry', label: 'Jewelry', femaleFocused: true },
  { value: 'accessory', label: 'Accessory' },
  { value: 'bag', label: 'Bag' },
  { value: 'purse', label: 'Purse', femaleFocused: true },
  { value: 'other', label: 'Other' },
]

export const clothingStatuses: Array<{ value: ClothingStatus; label: string }> = [
  { value: 'active', label: 'Active' },
  { value: 'archived', label: 'Archived' },
  { value: 'laundry', label: 'Laundry' },
  { value: 'unavailable', label: 'Unavailable' },
]

export const defaultClothingItemDraft: ClothingItemDraft = {
  name: '',
  brand: '',
  category: 'shirt',
  quantity: 1,
  color: '',
  material: '',
  pattern: '',
  notes: '',
  status: 'active',
}

const clothingCategoryValues = clothingCategories.map((category) => category.value)
const clothingStatusValues = clothingStatuses.map((status) => status.value)

function requireFirestore() {
  if (!db) {
    throw new Error('Firebase is not configured.')
  }

  return db
}

function clothingItemsCollection(userId: string) {
  return collection(requireFirestore(), 'users', userId, 'clothingItems')
}

function clothingItemDoc(userId: string, itemId: string) {
  return doc(requireFirestore(), 'users', userId, 'clothingItems', itemId)
}

function stringValue(value: unknown) {
  return typeof value === 'string' ? value : ''
}

function numberValue(value: unknown, fallback = 0) {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback
}

function categoryValue(value: unknown): ClothingCategory {
  return typeof value === 'string' && clothingCategoryValues.includes(value as ClothingCategory)
    ? (value as ClothingCategory)
    : 'other'
}

function statusValue(value: unknown): ClothingStatus {
  return typeof value === 'string' && clothingStatusValues.includes(value as ClothingStatus)
    ? (value as ClothingStatus)
    : 'active'
}

function normalizeDraft(draft: ClothingItemDraft) {
  const normalized = {
    name: draft.name.trim(),
    brand: draft.brand.trim(),
    category: draft.category,
    quantity: Math.max(1, Math.floor(draft.quantity || 1)),
    color: draft.color.trim(),
    material: draft.material.trim(),
    pattern: draft.pattern.trim(),
    notes: draft.notes.trim(),
    status: draft.status,
  }

  return {
    ...normalized,
    categoryRawValue: normalized.category,
    statusRawValue: normalized.status,
  }
}

function normalizeItem(id: string, data: Record<string, unknown>): ClothingItem {
  return {
    id,
    name: stringValue(data.name),
    brand: stringValue(data.brand),
    category: categoryValue(data.category ?? data.categoryRawValue),
    quantity: Math.max(1, Math.floor(numberValue(data.quantity, 1))),
    color: stringValue(data.color),
    material: stringValue(data.material),
    pattern: stringValue(data.pattern),
    notes: stringValue(data.notes),
    status: statusValue(data.status ?? data.statusRawValue),
    wearCount: Math.max(0, Math.floor(numberValue(data.wearCount, 0))),
    lastWornAt: stringValue(data.lastWornAt),
  }
}

export function categoryOptionsForWearer(wearerProfile: WearerProfile) {
  if (wearerProfile === 'male') {
    return clothingCategories.filter((category) => !category.femaleFocused)
  }

  return clothingCategories
}

export function categoryLabel(category: ClothingCategory) {
  return clothingCategories.find((option) => option.value === category)?.label ?? 'Other'
}

export function statusLabel(status: ClothingStatus) {
  return clothingStatuses.find((option) => option.value === status)?.label ?? 'Active'
}

export function subscribeToClothingItems(
  userId: string,
  onItems: (items: ClothingItem[]) => void,
  onError: (error: FirestoreError) => void,
): Unsubscribe {
  return onSnapshot(
    clothingItemsCollection(userId),
    (snapshot) => {
      const items = snapshot.docs
        .map((itemSnapshot) => normalizeItem(itemSnapshot.id, itemSnapshot.data()))
        .sort((first, second) => {
          const firstKey = `${categoryLabel(first.category)} ${first.name}`.toLowerCase()
          const secondKey = `${categoryLabel(second.category)} ${second.name}`.toLowerCase()
          return firstKey.localeCompare(secondKey)
        })

      onItems(items)
    },
    onError,
  )
}

export async function saveClothingItem(
  userId: string,
  draft: ClothingItemDraft,
  itemId?: string,
) {
  const payload = normalizeDraft(draft)

  if (!payload.name) {
    throw new Error('Item name is required.')
  }

  if (itemId) {
    await updateDoc(clothingItemDoc(userId, itemId), {
      ...payload,
      updatedAt: serverTimestamp(),
    })
    return
  }

  await addDoc(clothingItemsCollection(userId), {
    ...payload,
    wearCount: 0,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  })
}

export async function saveClothingItems(userId: string, drafts: ClothingItemDraft[]) {
  const normalizedDrafts = drafts.map(normalizeDraft)

  if (normalizedDrafts.length === 0) {
    throw new Error('Add at least one clothing item first.')
  }

  const missingName = normalizedDrafts.find((draft) => !draft.name)

  if (missingName) {
    throw new Error('Every imported item needs a name.')
  }

  const batch = writeBatch(requireFirestore())
  const itemsCollection = clothingItemsCollection(userId)

  normalizedDrafts.forEach((payload) => {
    const itemRef = doc(itemsCollection)
    batch.set(itemRef, {
      ...payload,
      wearCount: 0,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    })
  })

  await batch.commit()
}

export async function deleteAllClothingItems(userId: string) {
  const snapshot = await getDocs(clothingItemsCollection(userId))
  const itemDocs = snapshot.docs

  for (let index = 0; index < itemDocs.length; index += 450) {
    const batch = writeBatch(requireFirestore())

    itemDocs.slice(index, index + 450).forEach((itemDoc) => {
      batch.delete(itemDoc.ref)
    })

    await batch.commit()
  }
}

export async function updateClothingItemStatus(
  userId: string,
  itemId: string,
  status: ClothingStatus,
) {
  await updateDoc(clothingItemDoc(userId, itemId), {
    status,
    updatedAt: serverTimestamp(),
  })
}

export async function deleteClothingItem(userId: string, itemId: string) {
  await deleteDoc(clothingItemDoc(userId, itemId))
}
