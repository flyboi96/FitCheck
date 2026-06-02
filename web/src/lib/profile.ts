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
  favoriteLooks: string
  preferredColors: string
  preferredFit: string
  temperatureSensitivity: TemperatureSensitivity
  statementPiecePreference: string
  dislikedCombinations: string
  rules: string
}

export type TemperatureSensitivity = 'runs_hot' | 'neutral' | 'runs_cold'

export type UserProfileDraft = Pick<
  UserProfile,
  | 'displayName'
  | 'gender'
  | 'styleDescription'
  | 'favoriteLooks'
  | 'preferredColors'
  | 'preferredFit'
  | 'temperatureSensitivity'
  | 'statementPiecePreference'
  | 'dislikedCombinations'
  | 'rules'
>

const wearerProfiles: WearerProfile[] = ['unspecified', 'male', 'female']
const temperatureSensitivities: TemperatureSensitivity[] = ['runs_hot', 'neutral', 'runs_cold']

const isWearerProfile = (value: unknown): value is WearerProfile =>
  typeof value === 'string' && wearerProfiles.includes(value as WearerProfile)

const isTemperatureSensitivity = (value: unknown): value is TemperatureSensitivity =>
  typeof value === 'string' && temperatureSensitivities.includes(value as TemperatureSensitivity)

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
    favoriteLooks: stringValue(data.favoriteLooks),
    preferredColors: stringValue(data.preferredColors),
    preferredFit: stringValue(data.preferredFit),
    temperatureSensitivity: isTemperatureSensitivity(data.temperatureSensitivity)
      ? data.temperatureSensitivity
      : 'neutral',
    statementPiecePreference: stringValue(data.statementPiecePreference),
    dislikedCombinations: stringValue(data.dislikedCombinations),
    rules: stringValue(data.rules),
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
  const normalizedDraft = normalizeProfileDraft(draft)

  await setDoc(
    ref,
    {
      uid: user.uid,
      email: user.email ?? '',
      displayName: trimmedDisplayName,
      gender: draft.gender,
      ...normalizedDraft,
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
    ...normalizedDraft,
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
    favoriteLooks: '',
    preferredColors: '',
    preferredFit: '',
    temperatureSensitivity: 'neutral',
    statementPiecePreference: '',
    dislikedCombinations: '',
    rules: '',
  })
}

function normalizeProfileDraft(draft: UserProfileDraft) {
  return {
    styleDescription: draft.styleDescription.trim(),
    favoriteLooks: draft.favoriteLooks.trim(),
    preferredColors: draft.preferredColors.trim(),
    preferredFit: draft.preferredFit.trim(),
    temperatureSensitivity: draft.temperatureSensitivity,
    statementPiecePreference: draft.statementPiecePreference.trim(),
    dislikedCombinations: draft.dislikedCombinations.trim(),
    rules: draft.rules.trim(),
  }
}

export function emptyUserProfileDraft(
  overrides: Partial<UserProfileDraft> = {},
): UserProfileDraft {
  return {
    displayName: '',
    gender: 'unspecified',
    styleDescription: '',
    favoriteLooks: '',
    preferredColors: '',
    preferredFit: '',
    temperatureSensitivity: 'neutral',
    statementPiecePreference: '',
    dislikedCombinations: '',
    rules: '',
    ...overrides,
  }
}

export function temperatureSensitivityLabel(value: TemperatureSensitivity) {
  switch (value) {
    case 'runs_hot':
      return 'I run hot'
    case 'runs_cold':
      return 'I run cold'
    case 'neutral':
      return 'Neutral'
  }
}

export function profileStyleSummary(profile: UserProfile | null) {
  if (!profile) {
    return ''
  }

  return [
    profile.styleDescription,
    profile.favoriteLooks ? `Favorite looks: ${profile.favoriteLooks}` : '',
    profile.preferredColors ? `Preferred colors: ${profile.preferredColors}` : '',
    profile.preferredFit ? `Preferred fit: ${profile.preferredFit}` : '',
    profile.statementPiecePreference
      ? `Statement pieces: ${profile.statementPiecePreference}`
      : '',
    profile.dislikedCombinations ? `Avoid: ${profile.dislikedCombinations}` : '',
    profile.rules ? `Rules: ${profile.rules}` : '',
    `Temperature comfort: ${temperatureSensitivityLabel(profile.temperatureSensitivity)}`,
  ]
    .filter(Boolean)
    .join('\n')
}
