import {
  doc,
  getDoc,
  onSnapshot,
  serverTimestamp,
  setDoc,
  type FirestoreError,
  type Unsubscribe,
} from 'firebase/firestore'
import { db } from './firebase'
import type { OutfitContext } from './outfits'

export type ContextStyleDefinition = {
  context: OutfitContext
  label: string
  definition: string
}

export type ContextStyleSettings = {
  definitions: ContextStyleDefinition[]
  extraNotes: string
}

const contextOptions: Array<{ value: OutfitContext; label: string }> = [
  { value: 'work', label: 'Work / Office' },
  { value: 'casual', label: 'Casual Day' },
  { value: 'travel', label: 'Travel Day' },
  { value: 'dinner', label: 'Dinner / Date' },
  { value: 'gym', label: 'Gym' },
]

export const defaultContextDefinitions: ContextStyleDefinition[] = contextOptions.map((context) => ({
  context: context.value,
  label: context.label,
  definition: defaultDefinitionForContext(context.value),
}))

export const defaultContextStyleSettings: ContextStyleSettings = {
  definitions: defaultContextDefinitions,
  extraNotes: '',
}

function requireFirestore() {
  if (!db) {
    throw new Error('Firebase is not configured.')
  }

  return db
}

function contextStylesDoc(userId: string) {
  return doc(requireFirestore(), 'users', userId, 'contextStyles', 'default')
}

export function subscribeToContextStyles(
  userId: string,
  onSettings: (settings: ContextStyleSettings) => void,
  onError: (error: FirestoreError) => void,
): Unsubscribe {
  return onSnapshot(
    contextStylesDoc(userId),
    (snapshot) => {
      onSettings(snapshot.exists() ? normalizeContextStyles(snapshot.data()) : defaultContextStyleSettings)
    },
    onError,
  )
}

export async function loadContextStyles(userId: string) {
  const snapshot = await getDoc(contextStylesDoc(userId))
  return snapshot.exists() ? normalizeContextStyles(snapshot.data()) : defaultContextStyleSettings
}

export async function saveContextStyles(userId: string, settings: ContextStyleSettings) {
  await setDoc(
    contextStylesDoc(userId),
    {
      definitions: settings.definitions.map((definition) => ({
        context: definition.context,
        label: definition.label,
        definition: definition.definition.trim(),
      })),
      extraNotes: settings.extraNotes.trim(),
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  )
}

export function contextStylesPrompt(settings: ContextStyleSettings) {
  const lines = settings.definitions.map(
    (definition) => `${definition.label}: ${definition.definition.trim()}`,
  )

  if (settings.extraNotes.trim()) {
    lines.push(`Additional personal context notes: ${settings.extraNotes.trim()}`)
  }

  return lines.join('\n')
}

function normalizeContextStyles(data: Record<string, unknown>): ContextStyleSettings {
  const definitions = Array.isArray(data.definitions)
    ? data.definitions
        .map((definition) => normalizeDefinition(definition))
        .filter((definition): definition is ContextStyleDefinition => Boolean(definition))
    : []
  const mergedDefinitions = defaultContextDefinitions.map((defaultDefinition) => {
    const savedDefinition = definitions.find(
      (definition) => definition.context === defaultDefinition.context,
    )
    return savedDefinition ?? defaultDefinition
  })

  return {
    definitions: mergedDefinitions,
    extraNotes: typeof data.extraNotes === 'string' ? data.extraNotes : '',
  }
}

function normalizeDefinition(value: unknown): ContextStyleDefinition | null {
  if (!value || typeof value !== 'object') {
    return null
  }

  const data = value as Record<string, unknown>
  const context = contextOptions.find((option) => option.value === data.context)

  if (!context) {
    return null
  }

  return {
    context: context.value,
    label: context.label,
    definition: typeof data.definition === 'string'
      ? data.definition
      : defaultDefinitionForContext(context.value),
  }
}

function defaultDefinitionForContext(context: OutfitContext) {
  switch (context) {
    case 'work':
      return 'Business casual or office-ready. Use a structured work top, tailored pants or equivalent polished bottom, and polished shoes. Avoid shorts, sweatpants, Crocs, clogs, slides, slippers, and gym clothes unless explicitly allowed.'
    case 'casual':
      return 'Everyday casual for errands, city walking, and relaxed non-work days. Prioritize comfort, weather fit, and simple color harmony. Sneakers, tees, casual shirts, shorts, chinos, and jeans are valid when weather and style rules allow.'
    case 'travel':
      return 'Travel day outfit for transit and packing efficiency. Prioritize comfort, rewear potential, airport practicality, easy layers, and shoes that work with the rest of the trip.'
    case 'dinner':
      return 'Dinner/date outfit with more polish than daily casual. Prefer intentional color pairing, cleaner shoes, and a shirt, sweater, dress, skirt, or tailored pieces that feel deliberate.'
    case 'gym':
      return 'Exercise outfit only. Use activewear, exercise shoes, and appropriate exercise socks. Do not include belts, dress accessories, leather boots, chinos, button-downs, or other non-workout pieces.'
  }
}
