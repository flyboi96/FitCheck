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
import {
  contextSlug,
  defaultContextDescription,
  defaultContextLabel,
  normalizeOutfitContext,
  outfitContexts,
  type OutfitContext,
  type OutfitContextOption,
} from './outfitContextCatalog'

export type ContextStyleDefinition = {
  context: OutfitContext
  label: string
  definition: string
}

export type ContextStyleSettings = {
  definitions: ContextStyleDefinition[]
  extraNotes: string
}

const contextOptions: Array<{ value: OutfitContext; label: string }> = outfitContexts.map((context) => ({
  value: context.value,
  label: context.label,
}))

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
        label: definition.label.trim() || defaultContextLabel(definition.context),
        definition: definition.definition.trim(),
      })),
      extraNotes: settings.extraNotes.trim(),
      customizedContexts: true,
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
  const shouldMergeDefaults = data.customizedContexts !== true
  const mergedDefinitions = shouldMergeDefaults
    ? [
        ...defaultContextDefinitions.map((defaultDefinition) => {
          const savedDefinition = definitions.find(
            (definition) => definition.context === defaultDefinition.context,
          )
          return savedDefinition ?? defaultDefinition
        }),
        ...definitions.filter(
          (definition) =>
            !defaultContextDefinitions.some(
              (defaultDefinition) => defaultDefinition.context === definition.context,
            ),
        ),
      ]
    : definitions

  return {
    definitions: deduplicateDefinitions(
      mergedDefinitions.length > 0 ? mergedDefinitions : defaultContextDefinitions,
    ),
    extraNotes: typeof data.extraNotes === 'string' ? data.extraNotes : '',
  }
}

function normalizeDefinition(value: unknown): ContextStyleDefinition | null {
  if (!value || typeof value !== 'object') {
    return null
  }

  const data = value as Record<string, unknown>
  const normalizedContext = normalizeOutfitContext(data.context)
  const context = contextOptions.find((option) => option.value === normalizedContext)
  const label =
    typeof data.label === 'string' && data.label.trim()
      ? data.label.trim()
      : context?.label ?? defaultContextLabel(normalizedContext)

  const definition =
    typeof data.definition === 'string' && data.definition.trim()
      ? data.definition
      : context?.value
        ? defaultDefinitionForContext(context.value)
        : defaultContextDescription(normalizedContext)

  return {
    context: normalizedContext,
    label,
    definition,
  }
}

function defaultDefinitionForContext(context: OutfitContext) {
  return defaultContextDescription(context)
}

export function contextOptionsFromSettings(settings: ContextStyleSettings): OutfitContextOption[] {
  return settings.definitions
    .map((definition) => ({
      value: definition.context,
      label: definition.label.trim() || defaultContextLabel(definition.context),
      description: definition.definition.trim() || defaultContextDescription(definition.context),
    }))
    .filter((option) => option.label.trim())
}

export function createCustomContextDefinition(
  label: string,
  existingDefinitions: ContextStyleDefinition[] = [],
): ContextStyleDefinition {
  const trimmedLabel = label.trim() || 'Custom Context'

  return {
    context: uniqueContextSlug(trimmedLabel, existingDefinitions),
    label: trimmedLabel,
    definition: '',
  }
}

function deduplicateDefinitions(definitions: ContextStyleDefinition[]) {
  const seenContexts = new Set<string>()

  return definitions.filter((definition) => {
    if (seenContexts.has(definition.context)) {
      return false
    }

    seenContexts.add(definition.context)
    return true
  })
}

function uniqueContextSlug(label: string, existingDefinitions: ContextStyleDefinition[]) {
  const baseSlug = contextSlug(label)
  const existingContexts = new Set([
    ...outfitContexts.map((context) => context.value),
    ...existingDefinitions.map((definition) => definition.context),
  ])

  if (!existingContexts.has(baseSlug)) {
    return baseSlug
  }

  for (let index = 2; index < 100; index += 1) {
    const candidate = `${baseSlug}${index}`
    if (!existingContexts.has(candidate)) {
      return candidate
    }
  }

  return `custom-${crypto.randomUUID()}`
}
