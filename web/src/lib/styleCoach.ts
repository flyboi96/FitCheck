import { type UserProfile, type UserProfileDraft } from './profile'
import { getAIProxySettings } from './settings'

type StyleProfileResponse = {
  styleDescription?: string
  favoriteLooks?: string
  preferredColors?: string
  preferredFit?: string
  dislikedCombinations?: string
  rules?: string
  boldness?: number
  error?: string
}

export async function buildStyleProfileFromAnswers({
  answers,
  currentDraft,
  profile,
}: {
  answers: string
  currentDraft: UserProfileDraft
  profile: UserProfile | null
}): Promise<Partial<UserProfileDraft>> {
  const settings = getAIProxySettings()
  const baseURL = settings.proxyUrl.trim().replace(/\/+$/, '')

  if (!baseURL) {
    throw new Error('AI proxy URL is not configured in More.')
  }

  const response = await fetch(`${baseURL}/style-profile-draft`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(settings.proxyToken.trim() ? { 'X-FitCheck-Token': settings.proxyToken.trim() } : {}),
    },
    body: JSON.stringify({
      wearerProfile: currentDraft.gender || profile?.gender || 'unspecified',
      currentStyleDescription: currentDraft.styleDescription,
      currentFavoriteLooks: currentDraft.favoriteLooks,
      currentPreferredColors: currentDraft.preferredColors,
      currentPreferredFit: currentDraft.preferredFit,
      currentDislikedCombinations: currentDraft.dislikedCombinations,
      currentRules: currentDraft.rules,
      currentBoldness: 3,
      questionnaireAnswers: answers.trim(),
    }),
  })
  const data = (await response.json().catch(() => ({}))) as StyleProfileResponse

  if (!response.ok) {
    throw new Error(data.error || 'AI style coach failed.')
  }

  const statementPiecePreference =
    currentDraft.statementPiecePreference.trim() ||
    ((data.boldness ?? 3) >= 4
      ? 'Use one bold item occasionally, balanced by neutral pieces.'
      : 'Keep bold items occasional and intentional.')

  return {
    styleDescription: stringValue(data.styleDescription, currentDraft.styleDescription),
    favoriteLooks: stringValue(data.favoriteLooks, currentDraft.favoriteLooks),
    preferredColors: stringValue(data.preferredColors, currentDraft.preferredColors),
    preferredFit: stringValue(data.preferredFit, currentDraft.preferredFit),
    dislikedCombinations: stringValue(
      data.dislikedCombinations,
      currentDraft.dislikedCombinations,
    ),
    rules: stringValue(data.rules, currentDraft.rules),
    statementPiecePreference,
  }
}

function stringValue(value: unknown, fallback: string) {
  return typeof value === 'string' ? value : fallback
}
