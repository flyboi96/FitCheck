import { type User } from 'firebase/auth'
import { doc, getDoc, serverTimestamp, setDoc } from 'firebase/firestore'
import { db } from './firebase'

export type WearerProfile = 'unspecified' | 'male' | 'female'

export type UserProfile = {
  uid: string
  email: string
  displayName: string
  gender: WearerProfile
  styleDescription: string
}

export type UserProfileDraft = Pick<UserProfile, 'displayName' | 'gender' | 'styleDescription'>

const wearerProfiles: WearerProfile[] = ['unspecified', 'male', 'female']

const isWearerProfile = (value: unknown): value is WearerProfile =>
  typeof value === 'string' && wearerProfiles.includes(value as WearerProfile)

const stringValue = (value: unknown, fallback = '') =>
  typeof value === 'string' ? value : fallback

const usersCollection = 'users'

function requireFirestore() {
  if (!db) {
    throw new Error('Firebase is not configured.')
  }

  return db
}

function userProfileDoc(uid: string) {
  return doc(requireFirestore(), usersCollection, uid)
}

function normalizeProfile(user: User, data: Record<string, unknown>): UserProfile {
  const genderSource = data.gender ?? data.wearerProfile

  return {
    uid: user.uid,
    email: stringValue(data.email, user.email ?? ''),
    displayName: stringValue(data.displayName, user.displayName ?? ''),
    gender: isWearerProfile(genderSource) ? genderSource : 'unspecified',
    styleDescription: stringValue(data.styleDescription),
  }
}

export async function getUserProfile(user: User): Promise<UserProfile | null> {
  const snapshot = await getDoc(userProfileDoc(user.uid))

  if (!snapshot.exists()) {
    return null
  }

  return normalizeProfile(user, snapshot.data())
}

export async function upsertUserProfile(
  user: User,
  draft: UserProfileDraft,
): Promise<UserProfile> {
  const ref = userProfileDoc(user.uid)
  const snapshot = await getDoc(ref)
  const trimmedDisplayName = draft.displayName.trim()
  const trimmedStyleDescription = draft.styleDescription.trim()

  await setDoc(
    ref,
    {
      uid: user.uid,
      email: user.email ?? '',
      displayName: trimmedDisplayName,
      gender: draft.gender,
      styleDescription: trimmedStyleDescription,
      ...(snapshot.exists() ? {} : { createdAt: serverTimestamp() }),
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  )

  return {
    uid: user.uid,
    email: user.email ?? '',
    displayName: trimmedDisplayName,
    gender: draft.gender,
    styleDescription: trimmedStyleDescription,
  }
}

export async function ensureUserProfile(user: User): Promise<UserProfile> {
  const existingProfile = await getUserProfile(user)

  if (existingProfile) {
    return existingProfile
  }

  return upsertUserProfile(user, {
    displayName: user.displayName ?? '',
    gender: 'unspecified',
    styleDescription: '',
  })
}
