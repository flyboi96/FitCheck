import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  writeBatch,
} from 'firebase/firestore'
import { db } from './firebase'

type BackupDocument = {
  version: 1
  exportedAt: string
  profile: Record<string, unknown> | null
  clothingItems: BackupRecord[]
  plans: BackupRecord[]
  outfits: BackupRecord[]
  wearLogs: BackupRecord[]
  outfitFeedback: BackupRecord[]
  avatars: BackupRecord[]
  contextStyles: BackupRecord[]
}

type BackupRecord = {
  id: string
  data: Record<string, unknown>
}

const backupSubcollections = [
  'clothingItems',
  'plans',
  'outfits',
  'wearLogs',
  'outfitFeedback',
  'avatars',
  'contextStyles',
] as const

function requireFirestore() {
  if (!db) {
    throw new Error('Firebase is not configured.')
  }

  return db
}

function userDoc(userId: string) {
  return doc(requireFirestore(), 'users', userId)
}

function userSubcollection(userId: string, name: (typeof backupSubcollections)[number]) {
  return collection(requireFirestore(), 'users', userId, name)
}

function userSubcollectionDoc(
  userId: string,
  name: (typeof backupSubcollections)[number],
  recordId: string,
) {
  return doc(requireFirestore(), 'users', userId, name, recordId)
}

export async function exportFitCheckBackup(userId: string) {
  const profileSnapshot = await getDoc(userDoc(userId))
  const backup: BackupDocument = {
    version: 1,
    exportedAt: new Date().toISOString(),
    profile: profileSnapshot.exists() ? cleanFirestoreData(profileSnapshot.data()) : null,
    clothingItems: await exportCollection(userId, 'clothingItems'),
    plans: await exportCollection(userId, 'plans'),
    outfits: await exportCollection(userId, 'outfits'),
    wearLogs: await exportCollection(userId, 'wearLogs'),
    outfitFeedback: await exportCollection(userId, 'outfitFeedback'),
    avatars: await exportCollection(userId, 'avatars'),
    contextStyles: await exportCollection(userId, 'contextStyles'),
  }

  return JSON.stringify(backup, null, 2)
}

export function downloadBackup(json: string) {
  const blob = new Blob([json], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  const date = new Date().toISOString().slice(0, 10)

  link.href = url
  link.download = `fitcheck-backup-${date}.json`
  link.click()
  URL.revokeObjectURL(url)
}

export async function importFitCheckBackup(userId: string, file: File) {
  const text = await file.text()
  const backup = parseBackup(text)

  await replaceUserData(userId, backup)
}

async function exportCollection(
  userId: string,
  name: (typeof backupSubcollections)[number],
): Promise<BackupRecord[]> {
  const snapshot = await getDocs(userSubcollection(userId, name))
  return snapshot.docs.map((record) => ({
    id: record.id,
    data: cleanFirestoreData(record.data()),
  }))
}

async function replaceUserData(userId: string, backup: BackupDocument) {
  const batch = writeBatch(requireFirestore())

  for (const name of backupSubcollections) {
    const snapshot = await getDocs(userSubcollection(userId, name))
    snapshot.docs.forEach((record) => batch.delete(record.ref))
  }

  if (backup.profile) {
    batch.set(
      userDoc(userId),
      {
        ...restoreFirestoreData(backup.profile),
        updatedAt: serverTimestamp(),
      },
      { merge: true },
    )
  }

  addRecordsToBatch(batch, userId, 'clothingItems', backup.clothingItems)
  addRecordsToBatch(batch, userId, 'plans', backup.plans)
  addRecordsToBatch(batch, userId, 'outfits', backup.outfits)
  addRecordsToBatch(batch, userId, 'wearLogs', backup.wearLogs)
  addRecordsToBatch(batch, userId, 'outfitFeedback', backup.outfitFeedback)
  addRecordsToBatch(batch, userId, 'avatars', backup.avatars)
  addRecordsToBatch(batch, userId, 'contextStyles', backup.contextStyles)

  await batch.commit()
}

function addRecordsToBatch(
  batch: ReturnType<typeof writeBatch>,
  userId: string,
  name: (typeof backupSubcollections)[number],
  records: BackupRecord[],
) {
  records.forEach((record) => {
    batch.set(userSubcollectionDoc(userId, name, record.id), restoreFirestoreData(record.data))
  })
}

function parseBackup(text: string): BackupDocument {
  const parsed = JSON.parse(text) as Partial<BackupDocument>

  if (parsed.version !== 1) {
    throw new Error('Unsupported FitCheck backup version.')
  }

  return {
    version: 1,
    exportedAt: typeof parsed.exportedAt === 'string' ? parsed.exportedAt : new Date().toISOString(),
    profile: isRecord(parsed.profile) ? parsed.profile : null,
    clothingItems: recordsValue(parsed.clothingItems),
    plans: recordsValue(parsed.plans),
    outfits: recordsValue(parsed.outfits),
    wearLogs: recordsValue(parsed.wearLogs),
    outfitFeedback: recordsValue(parsed.outfitFeedback),
    avatars: recordsValue(parsed.avatars),
    contextStyles: recordsValue(parsed.contextStyles),
  }
}

function recordsValue(value: unknown): BackupRecord[] {
  if (!Array.isArray(value)) {
    return []
  }

  return value
    .map((record) => {
      if (!isRecord(record) || typeof record.id !== 'string' || !isRecord(record.data)) {
        return null
      }

      return {
        id: record.id,
        data: record.data,
      }
    })
    .filter((record): record is BackupRecord => Boolean(record))
}

function cleanFirestoreData(value: unknown): Record<string, unknown> {
  return JSON.parse(JSON.stringify(value, firestoreReplacer)) as Record<string, unknown>
}

function restoreFirestoreData(value: Record<string, unknown>) {
  return JSON.parse(JSON.stringify(value)) as Record<string, unknown>
}

function firestoreReplacer(_key: string, value: unknown) {
  const timestamp = value as { toDate?: () => Date } | undefined
  if (timestamp?.toDate) {
    return timestamp.toDate().toISOString()
  }

  return value
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value)
}

export async function clearImportedUserData(userId: string) {
  const batch = writeBatch(requireFirestore())

  for (const name of backupSubcollections) {
    const snapshot = await getDocs(userSubcollection(userId, name))
    snapshot.docs.forEach((record) => batch.delete(record.ref))
  }

  await batch.commit()
}

export async function deleteBackupImportedDocument(
  userId: string,
  name: (typeof backupSubcollections)[number],
  recordId: string,
) {
  await deleteDoc(userSubcollectionDoc(userId, name, recordId))
}
