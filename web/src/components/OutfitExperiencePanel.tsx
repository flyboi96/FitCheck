import { type FormEvent, useEffect, useMemo, useRef, useState } from 'react'
import {
  AlertTriangle,
  ArrowLeft,
  Bot,
  CalendarCheck,
  CheckCircle2,
  CloudSun,
  Download,
  Edit3,
  Image as ImageIcon,
  LocateFixed,
  MapPin,
  MessageSquare,
  Package,
  RefreshCw,
  Save,
  Sparkles,
  ThumbsDown,
  ThumbsUp,
  Wand2,
  X,
} from 'lucide-react'
import { ClothingItemBrowser } from './ClothingItemBrowser'
import { ScoreDebugPanel } from './ScoreDebugPanel'
import { useClosetItems } from '../hooks/useClosetItems'
import { useContextStyles } from '../hooks/useContextStyles'
import { useSavedAvatar } from '../hooks/useSavedAvatar'
import { showAppToast } from '../lib/appToasts'
import { generateAvatarPreview, type AvatarPreview } from '../lib/avatar'
import {
  categoryOptionsForWearer,
  clothingItemImageURL,
  clothingStatuses,
  itemCanBeUsedForOutfits,
  saveClothingItem,
  updateClothingItemsStatus,
  type ClothingCategory,
  type ClothingItem,
  type ClothingItemDraft,
  type ClothingStatus,
} from '../lib/closet'
import { contextOptionsFromSettings } from '../lib/contextStyles'
import {
  saveDailyOutfit,
  subscribeToDailyOutfit,
  type DailyOutfit,
  type DailyOutfitStatus,
} from '../lib/dailyOutfits'
import { logOutfitWear } from '../lib/history'
import { categoryName } from '../lib/outfits'
import {
  defaultWeatherInput,
  generateOutfit,
  saveOutfitFeedback,
  scoreCustomOutfit,
  weatherSummary,
  type OutfitContext,
  type OutfitFeedbackType,
  type OutfitGenerationMode,
  type OutfitRecommendation,
  type WeatherInput,
} from '../lib/outfits'
import type { UserProfile } from '../lib/profile'
import { lookupWeatherAtCurrentLocation, lookupWeatherByLocation, todayWeatherDate } from '../lib/weather'

type OutfitExperienceView = 'setup' | 'result'

export function OutfitExperiencePanel({
  mode,
  profile,
  userId,
}: {
  mode: 'today' | 'build'
  profile: UserProfile | null
  userId: string
}) {
  const { error: closetError, isLoading, items } = useClosetItems(userId)
  const { settings: contextSettings } = useContextStyles(userId)
  const contextOptions = useMemo(
    () => contextOptionsFromSettings(contextSettings),
    [contextSettings],
  )
  const [context, setContext] = useState<OutfitContext>('work')
  const effectiveContext = contextOptions.some((option) => option.value === context)
    ? context
    : contextOptions[0]?.value ?? 'casual'
  const [weather, setWeather] = useState<WeatherInput>(defaultWeatherInput)
  const [selectedItemId, setSelectedItemId] = useState('')
  const [recommendation, setRecommendation] = useState<OutfitRecommendation | null>(null)
  const [view, setView] = useState<OutfitExperienceView>('setup')
  const [isGenerating, setIsGenerating] = useState(false)
  const [generationError, setGenerationError] = useState<string | null>(null)
  const [feedbackNote, setFeedbackNote] = useState('')
  const [feedbackMessage, setFeedbackMessage] = useState<string | null>(null)
  const [feedbackError, setFeedbackError] = useState<string | null>(null)
  const [isSavingFeedback, setIsSavingFeedback] = useState(false)
  const [isLoggingWear, setIsLoggingWear] = useState(false)
  const [wearLogMessage, setWearLogMessage] = useState<string | null>(null)
  const [wearLogError, setWearLogError] = useState<string | null>(null)
  const [dailyOutfit, setDailyOutfit] = useState<DailyOutfit | null>(null)
  const [dailyOutfitMessage, setDailyOutfitMessage] = useState<string | null>(null)
  const [dailyOutfitError, setDailyOutfitError] = useState<string | null>(null)
  const [isSavingDailyOutfit, setIsSavingDailyOutfit] = useState(false)
  const [isLookingUpWeather, setIsLookingUpWeather] = useState(false)
  const [weatherStatus, setWeatherStatus] = useState<string | null>(null)
  const [weatherError, setWeatherError] = useState<string | null>(null)
  const autoWeatherAttempted = useRef(false)
  const todayDate = todayWeatherDate()
  const effectiveContextLabel =
    contextOptions.find((option) => option.value === effectiveContext)?.label ?? effectiveContext

  const activeItems = useMemo(() => items.filter((item) => itemCanBeUsedForOutfits(item)), [items])
  const resultEditableItems = useMemo(() => {
    const recommendationItemIDs = new Set(recommendation?.items.map((item) => item.id) ?? [])
    return items.filter((item) => itemCanBeUsedForOutfits(item) || recommendationItemIDs.has(item.id))
  }, [items, recommendation])
  const selectedItem = activeItems.find((item) => item.id === selectedItemId)

  useEffect(() => {
    if (mode !== 'today') {
      return
    }

    return subscribeToDailyOutfit(
      userId,
      todayDate,
      (nextDailyOutfit) => {
        setDailyOutfit(nextDailyOutfit)
        setDailyOutfitError(null)
      },
      (error) => {
        setDailyOutfitError(error.message)
      },
    )
  }, [mode, todayDate, userId])

  useEffect(() => {
    if (mode !== 'today' || !dailyOutfit || recommendation || items.length === 0) {
      return
    }

    const savedRecommendation = recommendationFromDailyOutfit(dailyOutfit, items, weather, profile)

    if (!savedRecommendation) {
      const errorTimer = window.setTimeout(() => {
        setDailyOutfitError('Saved outfit has no matching closet items.')
      }, 0)
      return () => window.clearTimeout(errorTimer)
    }

    const restoreTimer = window.setTimeout(() => {
      setContext(dailyOutfit.context)
      setRecommendation(savedRecommendation)
      setDailyOutfitMessage(
        dailyOutfit.status === 'wearing' ? 'Restored outfit you are wearing today.' : 'Restored planned outfit for today.',
      )
      setView('result')
    }, 0)
    return () => window.clearTimeout(restoreTimer)
  }, [dailyOutfit, items, mode, profile, recommendation, weather])

  useEffect(() => {
    if (mode !== 'today' || autoWeatherAttempted.current) {
      return
    }

    autoWeatherAttempted.current = true

    const timer = window.setTimeout(() => {
      setIsLookingUpWeather(true)
      setWeatherStatus("Trying today's full-day forecast for your location.")
      setWeatherError(null)

      lookupWeatherAtCurrentLocation(todayWeatherDate())
        .then((nextWeather) => {
          setWeather(nextWeather)
          setWeatherStatus(`Today forecast loaded: ${weatherSummary(nextWeather)}`)
        })
        .catch((error: unknown) => {
          setWeatherStatus('Using manual weather until you enter a city or allow location access.')
          setWeatherError(
            error instanceof Error ? error.message : 'Current-location weather lookup failed.',
          )
        })
        .finally(() => {
          setIsLookingUpWeather(false)
        })
    }, 0)

    return () => {
      window.clearTimeout(timer)
    }
  }, [mode])

  async function handleGenerate(generationMode: OutfitGenerationMode) {
    setIsGenerating(true)
    setGenerationError(null)
    setFeedbackMessage(null)
    setFeedbackError(null)
    setWearLogMessage(null)
    setWearLogError(null)
    setDailyOutfitMessage(null)
    setDailyOutfitError(null)
    showAppToast(generationMode === 'ai' ? 'Asking AI for an outfit...' : 'Generating a local outfit...', 'info')

    try {
      const nextRecommendation = await generateOutfit({
        closet: items,
        context: effectiveContext,
        generationMode,
        profile,
        selectedItemId: mode === 'build' ? selectedItemId || undefined : undefined,
        userId,
        weather,
      })
      setRecommendation(nextRecommendation)
      setView('result')
      showAppToast('Outfit generated.', 'success')
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Could not generate an outfit.'
      setGenerationError(message)
      showAppToast(message, 'error')
    } finally {
      setIsGenerating(false)
    }
  }

  async function handleWeatherLookup(useCurrentLocation: boolean) {
    setIsLookingUpWeather(true)
    setWeatherStatus(null)
    setWeatherError(null)
    showAppToast('Looking up full-day forecast...', 'info')

    try {
      const weatherDate = todayWeatherDate()
      const nextWeather = useCurrentLocation
        ? await lookupWeatherAtCurrentLocation(weatherDate)
        : await lookupWeatherByLocation(weather.location, weatherDate)
      setWeather(nextWeather)
      setWeatherStatus(`Today forecast updated: ${weatherSummary(nextWeather)}`)
      showAppToast('Full-day forecast updated.', 'success')
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Weather lookup failed.'
      setWeatherError(message)
      showAppToast(message, 'error')
    } finally {
      setIsLookingUpWeather(false)
    }
  }

  function updateDayTemperature(field: 'highTemperatureF' | 'lowTemperatureF', value: number) {
    const nextWeather = {
      ...weather,
      [field]: value,
    }
    const high = nextWeather.highTemperatureF
    const low = nextWeather.lowTemperatureF

    setWeather({
      ...nextWeather,
      temperatureF: Math.round((high + low) / 2),
      source: 'Manual full-day weather',
    })
  }

  async function handleFeedback(type: OutfitFeedbackType) {
    if (!recommendation) {
      return
    }

    setIsSavingFeedback(true)
    setFeedbackMessage(null)
    setFeedbackError(null)

    try {
      await saveOutfitFeedback({
        context: effectiveContext,
        feedback: type,
        note: feedbackNote,
        recommendation,
        userId,
        weather,
      })
      setFeedbackMessage('Feedback saved. Future AI requests include recent feedback.')
      setFeedbackNote('')
      showAppToast('Feedback saved.', 'success')
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Could not save feedback.'
      setFeedbackError(message)
      showAppToast(message, 'error')
    } finally {
      setIsSavingFeedback(false)
    }
  }

  async function handleLogWear(note: string) {
    if (!recommendation) {
      return
    }

    setIsLoggingWear(true)
    setWearLogMessage(null)
    setWearLogError(null)
    setDailyOutfitMessage(null)
    setDailyOutfitError(null)

    try {
      await logOutfitWear({
        context: effectiveContext,
        contextLabel: effectiveContextLabel,
        note,
        recommendation,
        userId,
        weather,
      })
      await saveDailyOutfit({
        context: effectiveContext,
        contextLabel: effectiveContextLabel,
        date: todayDate,
        recommendation,
        status: 'wearing',
        userId,
        weather,
      })
      await updateClothingItemsStatus(
        userId,
        recommendation.items.map((item) => item.id),
        'wearing',
      )
      setWearLogMessage('Wear logged. Items marked wearing and still available for outfit planning.')
      showAppToast('Wear logged.', 'success')
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Could not log wear.'
      setWearLogError(message)
      showAppToast(message, 'error')
    } finally {
      setIsLoggingWear(false)
    }
  }

  async function handleSaveDailyOutfit(status: DailyOutfitStatus) {
    if (!recommendation) {
      return
    }

    setIsSavingDailyOutfit(true)
    setDailyOutfitMessage(null)
    setDailyOutfitError(null)

    try {
      await saveDailyOutfit({
        context: effectiveContext,
        contextLabel: effectiveContextLabel,
        date: todayDate,
        recommendation,
        status,
        userId,
        weather,
      })

      if (status === 'wearing') {
        await logOutfitWear({
          context: effectiveContext,
          contextLabel: effectiveContextLabel,
          note: 'Marked wearing now.',
          recommendation,
          userId,
          weather,
        })
        await updateClothingItemsStatus(
          userId,
          recommendation.items.map((item) => item.id),
          'wearing',
        )
      }

      const message =
        status === 'wearing'
          ? 'Saved as wearing now. Items remain available for outfit planning.'
          : 'Saved for today. This outfit will restore when you return.'
      setDailyOutfitMessage(message)
      showAppToast(message, 'success')
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Could not save today outfit.'
      setDailyOutfitError(message)
      showAppToast(message, 'error')
    } finally {
      setIsSavingDailyOutfit(false)
    }
  }

  async function handleMoveRecommendationToLaundry() {
    if (!recommendation) {
      return
    }

    setIsSavingDailyOutfit(true)
    setDailyOutfitMessage(null)
    setDailyOutfitError(null)

    try {
      await updateClothingItemsStatus(
        userId,
        recommendation.items.map((item) => item.id),
        'laundry',
      )
      const message = 'Outfit items moved to laundry and removed from new outfit picks.'
      setDailyOutfitMessage(message)
      showAppToast(message, 'success')
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Could not move outfit to laundry.'
      setDailyOutfitError(message)
      showAppToast(message, 'error')
    } finally {
      setIsSavingDailyOutfit(false)
    }
  }

  async function handleMoveItemToLaundry(item: ClothingItem) {
    setIsSavingDailyOutfit(true)
    setDailyOutfitMessage(null)
    setDailyOutfitError(null)

    try {
      await updateClothingItemsStatus(userId, [item.id], 'laundry')
      const message = `${item.name} moved to laundry.`
      setDailyOutfitMessage(message)
      showAppToast(message, 'success')
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Could not move item to laundry.'
      setDailyOutfitError(message)
      showAppToast(message, 'error')
    } finally {
      setIsSavingDailyOutfit(false)
    }
  }

  if (view === 'result' && recommendation) {
    return (
      <div className="outfit-panel">
        <OutfitSubpageHeader
          onBack={() => setView('setup')}
          subtitle={mode === 'today' ? 'Today' : 'Build'}
          title={recommendation.source === 'ai' ? 'AI Outfit' : 'FitCheck Outfit'}
        />
        <OutfitResultCard
          feedbackNote={feedbackNote}
          feedbackError={feedbackError}
          feedbackMessage={feedbackMessage}
          context={effectiveContext}
          dailyOutfitError={dailyOutfitError}
          dailyOutfitMessage={dailyOutfitMessage}
          isSavingDailyOutfit={isSavingDailyOutfit}
          isSavingFeedback={isSavingFeedback}
          isLoggingWear={isLoggingWear}
          onMoveToLaundry={() => {
            void handleMoveRecommendationToLaundry()
          }}
          onMoveItemToLaundry={(item) => {
            void handleMoveItemToLaundry(item)
          }}
          onFeedback={(type) => {
            void handleFeedback(type)
          }}
          onLogWear={(note) => {
            void handleLogWear(note)
          }}
          onRecommendationChange={setRecommendation}
          onNoteChange={setFeedbackNote}
          onSaveDailyOutfit={(status) => {
            void handleSaveDailyOutfit(status)
          }}
          profile={profile}
          recommendation={recommendation}
          resultEditableItems={resultEditableItems}
          userId={userId}
          weather={weather}
          wearLogError={wearLogError}
          wearLogMessage={wearLogMessage}
        />
      </div>
    )
  }

  return (
    <div className="outfit-panel">
      <div className="weather-context-card">
        <div className="section-title">
          <CloudSun size={20} aria-hidden="true" />
          <div>
            <p className="eyebrow">{mode === 'today' ? 'Today' : 'Build'}</p>
            <h2>{mode === 'today' ? 'Outfit Context' : 'Build Around Item'}</h2>
          </div>
        </div>

        <div className="two-column-fields">
          <label className="form-field">
            <span>Context</span>
            <select
              onChange={(event) => setContext(event.target.value as OutfitContext)}
              value={effectiveContext}
            >
              {contextOptions.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </label>

          <label className="form-field">
            <span>Location</span>
            <input
              onChange={(event) => setWeather({ ...weather, location: event.target.value })}
              placeholder="Djibouti"
              type="text"
              value={weather.location}
            />
          </label>
        </div>

        <p className="helper-text">
          {contextOptions.find((option) => option.value === effectiveContext)?.description}
        </p>

        <div className="weather-source-card">
          <strong>Today's Forecast Source</strong>
          <span>{weather.location.trim() ? weatherSummary(weather) : 'Manual full-day weather values until current location or city lookup succeeds.'}</span>
        </div>

        <div className="weather-actions">
          <button
            type="button"
            className="secondary-button"
            disabled={isLookingUpWeather}
            onClick={() => {
              void handleWeatherLookup(false)
            }}
          >
            {isLookingUpWeather ? <span className="spinner small" aria-hidden="true" /> : <MapPin size={20} />}
            Look Up Full-Day Forecast
          </button>
          <button
            type="button"
            className="secondary-button"
            disabled={isLookingUpWeather}
            onClick={() => {
              void handleWeatherLookup(true)
            }}
          >
            <LocateFixed size={20} aria-hidden="true" />
            Use My Location
          </button>
        </div>

        {weatherStatus ? <p className="success-message">{weatherStatus}</p> : null}
        {weatherError ? <p className="error-message">{weatherError}</p> : null}

        <div className="weather-grid">
          <label className="form-field">
            <span>Day High F</span>
            <input
              inputMode="numeric"
              onChange={(event) =>
                updateDayTemperature('highTemperatureF', numberInput(event.target.value, 75))
              }
              type="number"
              value={weather.highTemperatureF}
            />
          </label>

          <label className="form-field">
            <span>Day Low F</span>
            <input
              inputMode="numeric"
              onChange={(event) =>
                updateDayTemperature('lowTemperatureF', numberInput(event.target.value, 75))
              }
              type="number"
              value={weather.lowTemperatureF}
            />
          </label>

          <label className="form-field">
            <span>Condition</span>
            <input
              onChange={(event) => setWeather({ ...weather, condition: event.target.value })}
              placeholder="Clear"
              type="text"
              value={weather.condition}
            />
          </label>

          <label className="form-field">
            <span>Humidity</span>
            <input
              inputMode="numeric"
              max={100}
              min={0}
              onChange={(event) =>
                setWeather({ ...weather, humidityPercent: numberInput(event.target.value, 45) })
              }
              type="number"
              value={weather.humidityPercent}
            />
          </label>

          <label className="form-field">
            <span>Wind mph</span>
            <input
              inputMode="numeric"
              min={0}
              onChange={(event) =>
                setWeather({ ...weather, windMph: numberInput(event.target.value, 5) })
              }
              type="number"
              value={weather.windMph}
            />
          </label>
        </div>

        <label className="toggle-row">
          <input
            checked={weather.isRaining}
            onChange={(event) => setWeather({ ...weather, isRaining: event.target.checked })}
            type="checkbox"
          />
          <span>Rain or storm risk</span>
        </label>

        {mode === 'build' ? (
          <div className="form-field">
            <span>Required Item</span>
            <ClothingItemBrowser
              allowEmptySelection
              compact
              emptySelectionLabel="No required item"
              items={activeItems}
              onSelectionChange={(itemIDs) => setSelectedItemId(itemIDs[0] ?? '')}
              selectedItemIDs={selectedItemId ? [selectedItemId] : []}
              selectionMode="single"
            />
          </div>
        ) : null}

        {mode === 'build' && selectedItem ? (
          <p className="helper-text">Building around: {selectedItem.name}</p>
        ) : null}

        <div className="generation-actions sticky-action-bar">
          <button
            type="button"
            className="primary-button"
            disabled={isGenerating || activeItems.length === 0}
            onClick={() => {
              void handleGenerate('ai')
            }}
          >
            {isGenerating ? <span className="spinner small" aria-hidden="true" /> : <Sparkles size={20} />}
            Ask AI First
          </button>

          <button
            type="button"
            className="secondary-button"
            disabled={isGenerating || activeItems.length === 0}
            onClick={() => {
              void handleGenerate('local')
            }}
          >
            <Wand2 size={20} aria-hidden="true" />
            Local Pick
          </button>
        </div>
      </div>

      {isLoading ? (
        <div className="placeholder-panel">
          <span className="spinner small" aria-hidden="true" />
          <div>
            <h3>Loading closet</h3>
            <p>Reading your active clothing items from Firestore.</p>
          </div>
        </div>
      ) : null}

      {closetError ? <p className="error-message">{closetError}</p> : null}
      {generationError ? <p className="error-message">{generationError}</p> : null}

      {recommendation ? (
        <button type="button" className="secondary-button" onClick={() => setView('result')}>
          <CheckCircle2 size={20} aria-hidden="true" />
          View Current Outfit
        </button>
      ) : null}

      {!isLoading && activeItems.length === 0 ? (
        <div className="empty-state">
          <AlertTriangle size={24} aria-hidden="true" />
          <h3>No active closet items</h3>
          <p>Add active items in Closet before generating outfits.</p>
        </div>
      ) : null}
    </div>
  )
}

function OutfitSubpageHeader({
  onBack,
  subtitle,
  title,
}: {
  onBack: () => void
  subtitle: string
  title: string
}) {
  return (
    <div className="subpage-header">
      <button type="button" className="icon-button" onClick={onBack} aria-label="Back">
        <ArrowLeft size={22} />
      </button>
      <div>
        <p className="eyebrow">{subtitle}</p>
        <h2>{title}</h2>
      </div>
    </div>
  )
}

function OutfitResultCard({
  context,
  dailyOutfitError,
  dailyOutfitMessage,
  feedbackError,
  feedbackMessage,
  feedbackNote,
  isSavingDailyOutfit,
  isSavingFeedback,
  isLoggingWear,
  onMoveToLaundry,
  onMoveItemToLaundry,
  onFeedback,
  onLogWear,
  onNoteChange,
  onRecommendationChange,
  onSaveDailyOutfit,
  profile,
  recommendation,
  resultEditableItems,
  userId,
  weather,
  wearLogError,
  wearLogMessage,
}: {
  context: OutfitContext
  dailyOutfitError: string | null
  dailyOutfitMessage: string | null
  feedbackError: string | null
  feedbackMessage: string | null
  feedbackNote: string
  isSavingDailyOutfit: boolean
  isSavingFeedback: boolean
  isLoggingWear: boolean
  onMoveToLaundry: () => void
  onMoveItemToLaundry: (item: ClothingItem) => void
  onFeedback: (type: OutfitFeedbackType) => void
  onLogWear: (note: string) => void
  onNoteChange: (note: string) => void
  onRecommendationChange: (recommendation: OutfitRecommendation) => void
  onSaveDailyOutfit: (status: DailyOutfitStatus) => void
  profile: UserProfile | null
  recommendation: OutfitRecommendation
  resultEditableItems: ClothingItem[]
  userId: string
  weather: WeatherInput
  wearLogError: string | null
  wearLogMessage: string | null
}) {
  const { avatar: savedAvatar } = useSavedAvatar(userId)
  const [avatarFile, setAvatarFile] = useState<File | null>(null)
  const [avatarPreview, setAvatarPreview] = useState<AvatarPreview | null>(null)
  const [isGeneratingAvatar, setIsGeneratingAvatar] = useState(false)
  const [avatarError, setAvatarError] = useState<string | null>(null)
  const [wearNote, setWearNote] = useState('')
  const [selectedItemIDs, setSelectedItemIDs] = useState(() =>
    recommendation.items.map((item) => item.id),
  )
  const [editMessage, setEditMessage] = useState<string | null>(null)
  const [editError, setEditError] = useState<string | null>(null)
  const [editingItem, setEditingItem] = useState<ClothingItem | null>(null)
  const previousRecommendationId = useRef(recommendation.id)

  useEffect(() => {
    if (previousRecommendationId.current === recommendation.id) {
      return
    }

    previousRecommendationId.current = recommendation.id
    setSelectedItemIDs(recommendation.items.map((item) => item.id))
    setEditingItem(null)
    setEditMessage(null)
    setEditError(null)
  }, [recommendation])

  const activeItemsById = useMemo(
    () => new Map(resultEditableItems.map((item) => [item.id, item])),
    [resultEditableItems],
  )

  function saveOutfitItemEdits() {
    const selectedItems = selectedItemIDs
      .map((itemId) => activeItemsById.get(itemId))
      .filter((item): item is ClothingItem => Boolean(item))

    if (selectedItems.length === 0) {
      setEditMessage(null)
      setEditError('Choose at least one clothing item.')
      return
    }

    const rescoredRecommendation = scoreCustomOutfit({
      context,
      items: selectedItems,
      profile,
      source: recommendation.source,
      weather,
    })

    onRecommendationChange({
      ...rescoredRecommendation,
      id: recommendation.id,
      rationale: 'Edited outfit rescored from your selected closet items.',
    })
    setEditError(null)
    setEditMessage('Outfit updated and score recalculated.')
  }

  function handleItemSaved(updatedItem: ClothingItem) {
    const updatedItems = recommendation.items.map((item) =>
      item.id === updatedItem.id ? updatedItem : item,
    )
    const rescoredRecommendation = scoreCustomOutfit({
      context,
      items: updatedItems,
      profile,
      source: recommendation.source,
      weather,
    })

    onRecommendationChange({
      ...rescoredRecommendation,
      id: recommendation.id,
      rationale: 'Closet item edited and outfit rescored.',
    })
    setEditingItem(updatedItem)
    setEditError(null)
    setEditMessage(`${updatedItem.name} saved. Outfit score recalculated.`)
  }

  async function handleAvatarPreview() {
    if (!savedAvatar && !avatarFile) {
      setAvatarError('Choose a full-body reference photo or save an avatar in More first.')
      return
    }

    setIsGeneratingAvatar(true)
    setAvatarError(null)

    try {
      setAvatarPreview(
        await generateAvatarPreview({
          file: avatarFile,
          profile,
          recommendation,
          savedAvatar,
          weather,
        }),
      )
    } catch (error) {
      setAvatarError(error instanceof Error ? error.message : 'Avatar preview failed.')
    } finally {
      setIsGeneratingAvatar(false)
    }
  }

  return (
    <article className="recommendation-card">
      <div className="recommendation-header">
        <div>
          <p className="eyebrow">{recommendation.source === 'ai' ? 'AI First' : 'Local Pick'}</p>
          <h2>{recommendation.source === 'ai' ? 'AI Outfit' : 'FitCheck Outfit'}</h2>
          <p className="helper-text">{weatherSummary(weather)}</p>
        </div>
        <div className={`score-badge ${scoreClass(recommendation.score)}`}>
          <strong>{recommendation.score}</strong>
          <span>{recommendation.scoreLabel}</span>
        </div>
      </div>

      <div className="outfit-item-list">
        {recommendation.items.map((item) => {
          const imageURL = clothingItemImageURL(item)

          return (
            <div className={`outfit-item-row${imageURL ? ' has-thumbnail' : ''}`} key={item.id}>
              {imageURL ? <img className="item-photo-thumb small" alt="" src={imageURL} /> : null}
              <div>
                <strong>{item.name}</strong>
                <span>
                  {categoryName(item.category)}
                  {item.brand ? ` - ${item.brand}` : ''}
                  {item.material ? ` - ${item.material}` : ''}
                </span>
                <small>
                  {item.wearCount}x overall - {item.wearsSinceClean}x since clean
                </small>
              </div>
              <div className="item-inline-actions">
                <span className="quantity-chip">Qty {item.quantity}</span>
                <button
                  type="button"
                  className="ghost-button icon-sized"
                  onClick={() => setEditingItem(item)}
                  aria-label={`Edit ${item.name}`}
                >
                  <Edit3 size={18} aria-hidden="true" />
                </button>
                <button
                  type="button"
                  className="ghost-button icon-sized"
                  disabled={isSavingDailyOutfit}
                  onClick={() => onMoveItemToLaundry(item)}
                  aria-label={`Move ${item.name} to laundry`}
                >
                  <Package size={18} aria-hidden="true" />
                </button>
              </div>
            </div>
          )
        })}
      </div>

      {editMessage ? <p className="success-message">{editMessage}</p> : null}
      {editError ? <p className="error-message">{editError}</p> : null}

      {editingItem ? (
        <QuickClothingItemEditor
          item={editingItem}
          key={editingItem.id}
          onCancel={() => setEditingItem(null)}
          onSaved={handleItemSaved}
          profile={profile}
          userId={userId}
        />
      ) : null}

      <details className="edit-section">
        <summary>Edit outfit items</summary>
        <p className="helper-text">
          Add or remove owned items, then save to recalculate the outfit score.
        </p>
        <ClothingItemBrowser
          compact
          items={resultEditableItems}
          onSelectionChange={setSelectedItemIDs}
          selectedItemIDs={selectedItemIDs}
          selectionMode="multiple"
        />
        <button type="button" className="secondary-button" onClick={saveOutfitItemEdits}>
          <Save size={20} aria-hidden="true" />
          Save Outfit Items
        </button>
      </details>

      <div className="wear-log-panel">
        <div className="generation-actions">
          <button
            type="button"
            className="secondary-button"
            disabled={isSavingDailyOutfit}
            onClick={() => onSaveDailyOutfit('planned')}
          >
            {isSavingDailyOutfit ? (
              <span className="spinner small" aria-hidden="true" />
            ) : (
              <Save size={20} aria-hidden="true" />
            )}
            Save for Today
          </button>
          <button
            type="button"
            className="secondary-button"
            disabled={isSavingDailyOutfit}
            onClick={() => onSaveDailyOutfit('wearing')}
          >
            <CalendarCheck size={20} aria-hidden="true" />
            Wearing Now
          </button>
          <button
            type="button"
            className="secondary-button"
            disabled={isSavingDailyOutfit}
            onClick={onMoveToLaundry}
          >
            <RefreshCw size={20} aria-hidden="true" />
            All to Laundry
          </button>
        </div>
        {dailyOutfitMessage ? <p className="success-message">{dailyOutfitMessage}</p> : null}
        {dailyOutfitError ? <p className="error-message">{dailyOutfitError}</p> : null}

        <label className="form-field">
          <span>Wear Note</span>
          <textarea
            onChange={(event) => setWearNote(event.target.value)}
            placeholder="Optional: where you wore it, what worked, or what to remember."
            rows={2}
            value={wearNote}
          />
        </label>
        <button
          type="button"
          className="primary-button"
          disabled={isLoggingWear}
          onClick={() => onLogWear(wearNote)}
        >
          {isLoggingWear ? (
            <span className="spinner small" aria-hidden="true" />
          ) : (
            <CalendarCheck size={20} aria-hidden="true" />
          )}
          Log Wear
        </button>
        {wearLogMessage ? <p className="success-message">{wearLogMessage}</p> : null}
        {wearLogError ? <p className="error-message">{wearLogError}</p> : null}
      </div>

      <div className="reason-block">
        <div className="section-title">
          {recommendation.source === 'ai' ? <Bot size={20} /> : <CheckCircle2 size={20} />}
          <h3>Why this works</h3>
        </div>
        <p>{recommendation.rationale}</p>
        <ul>
          {recommendation.reasons.map((reason) => (
            <li key={reason}>{reason}</li>
          ))}
        </ul>
      </div>

      {recommendation.cautions.length > 0 ? (
        <div className="caution-block">
          <div className="section-title">
            <AlertTriangle size={20} />
            <h3>Watch-outs</h3>
          </div>
          <ul>
            {recommendation.cautions.map((caution) => (
              <li key={caution}>{caution}</li>
            ))}
          </ul>
        </div>
      ) : null}

      <ScoreDebugPanel breakdown={recommendation.scoreBreakdown} />

      <details className="avatar-panel">
        <summary>Avatar Preview</summary>
        <div className="section-title">
          <ImageIcon size={20} aria-hidden="true" />
          <h3>Avatar Preview</h3>
        </div>
        <p className="helper-text">
          {savedAvatar
            ? 'Using your saved avatar from More. You can still upload a one-time reference photo to override it.'
            : 'Choose from Photos or take a full-body reference photo with head, hair, and shoes visible.'}
        </p>
        <label className="form-field">
          <span>Reference Photo</span>
          <input
            accept="image/*"
            onChange={(event) => setAvatarFile(event.target.files?.[0] ?? null)}
            type="file"
          />
        </label>
        {avatarFile ? <p className="helper-text">Selected: {avatarFile.name}</p> : null}
        <button
          type="button"
          className="secondary-button"
          disabled={isGeneratingAvatar}
          onClick={() => {
            void handleAvatarPreview()
          }}
        >
          {isGeneratingAvatar ? <span className="spinner small" aria-hidden="true" /> : <ImageIcon size={20} />}
          {savedAvatar ? 'Generate with Saved Avatar' : 'Generate Avatar'}
        </button>
        {avatarError ? <p className="error-message">{avatarError}</p> : null}
        {avatarPreview ? (
          <div className="avatar-preview-result">
            <img alt="Generated avatar wearing selected outfit" src={avatarPreview.imageURL} />
            <p className="helper-text">{avatarPreview.promptSummary}</p>
            <a className="secondary-button" download="fitcheck-avatar.png" href={avatarPreview.imageURL}>
              <Download size={20} aria-hidden="true" />
              Save Image
            </a>
          </div>
        ) : null}
      </details>

      <div className="feedback-panel">
        <label className="form-field">
          <span>Feedback for future picks</span>
          <textarea
            onChange={(event) => onNoteChange(event.target.value)}
            placeholder="What worked or did not work?"
            rows={3}
            value={feedbackNote}
          />
        </label>

        <div className="feedback-actions sticky-action-bar">
          <button
            type="button"
            className="ghost-button"
            disabled={isSavingFeedback}
            onClick={() => onFeedback('liked')}
          >
            <ThumbsUp size={18} aria-hidden="true" />
            Liked
          </button>
          <button
            type="button"
            className="ghost-button"
            disabled={isSavingFeedback}
            onClick={() => onFeedback('issue')}
          >
            <MessageSquare size={18} aria-hidden="true" />
            Issue
          </button>
          <button
            type="button"
            className="danger-button"
            disabled={isSavingFeedback}
            onClick={() => onFeedback('rejected')}
          >
            <ThumbsDown size={18} aria-hidden="true" />
            Reject
          </button>
        </div>

        {feedbackMessage ? <p className="success-message">{feedbackMessage}</p> : null}
        {feedbackError ? <p className="error-message">{feedbackError}</p> : null}
        {isSavingFeedback ? (
          <p className="helper-text">
            <RefreshCw size={14} aria-hidden="true" /> Saving feedback
          </p>
        ) : null}
      </div>
    </article>
  )
}

function QuickClothingItemEditor({
  item,
  onCancel,
  onSaved,
  profile,
  userId,
}: {
  item: ClothingItem
  onCancel: () => void
  onSaved: (item: ClothingItem) => void
  profile: UserProfile | null
  userId: string
}) {
  const [draft, setDraft] = useState<ClothingItemDraft>(() => clothingItemDraftFromItem(item))
  const [isSaving, setIsSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const categoryOptions = categoryOptionsForWearer(profile?.gender ?? 'unspecified')

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setIsSaving(true)
    setError(null)

    try {
      await saveClothingItem(userId, draft, item.id)
      onSaved({
        ...item,
        name: draft.name.trim(),
        brand: draft.brand.trim(),
        category: draft.category,
        quantity: Math.max(1, Math.floor(draft.quantity || 1)),
        color: draft.color.trim(),
        material: draft.material.trim(),
        pattern: draft.pattern.trim(),
        notes: draft.notes.trim(),
        imageBase64: draft.imageBase64.trim(),
        imageMimeType: draft.imageMimeType.trim(),
        status: draft.status,
      })
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Could not save clothing item.')
    } finally {
      setIsSaving(false)
    }
  }

  return (
    <form className="quick-edit-card" onSubmit={handleSubmit}>
      <div className="form-title-row">
        <div>
          <p className="eyebrow">Closet item</p>
          <h3>Edit {item.name}</h3>
        </div>
        <button type="button" className="icon-button" onClick={onCancel} aria-label="Close item editor">
          <X size={20} />
        </button>
      </div>

      <label className="form-field">
        <span>Name</span>
        <input
          onChange={(event) => setDraft({ ...draft, name: event.target.value })}
          required
          type="text"
          value={draft.name}
        />
      </label>

      <div className="two-column-fields">
        <label className="form-field compact">
          <span>Category</span>
          <select
            onChange={(event) =>
              setDraft({ ...draft, category: event.target.value as ClothingCategory })
            }
            value={draft.category}
          >
            {categoryOptions.map((category) => (
              <option key={category.value} value={category.value}>
                {category.label}
              </option>
            ))}
          </select>
        </label>

        <label className="form-field compact">
          <span>Quantity</span>
          <input
            min={1}
            onChange={(event) =>
              setDraft({ ...draft, quantity: quantityInputValue(event.target.value) })
            }
            type="number"
            value={draft.quantity || ''}
          />
        </label>
      </div>

      <div className="two-column-fields">
        <label className="form-field compact">
          <span>Brand</span>
          <input
            onChange={(event) => setDraft({ ...draft, brand: event.target.value })}
            type="text"
            value={draft.brand}
          />
        </label>

        <label className="form-field compact">
          <span>Status</span>
          <select
            onChange={(event) =>
              setDraft({ ...draft, status: event.target.value as ClothingStatus })
            }
            value={draft.status}
          >
            {clothingStatuses.map((status) => (
              <option key={status.value} value={status.value}>
                {status.label}
              </option>
            ))}
          </select>
        </label>
      </div>

      <div className="two-column-fields">
        <label className="form-field compact">
          <span>Color</span>
          <input
            onChange={(event) => setDraft({ ...draft, color: event.target.value })}
            type="text"
            value={draft.color}
          />
        </label>

        <label className="form-field compact">
          <span>Pattern</span>
          <input
            onChange={(event) => setDraft({ ...draft, pattern: event.target.value })}
            type="text"
            value={draft.pattern}
          />
        </label>
      </div>

      <label className="form-field">
        <span>Material</span>
        <input
          onChange={(event) => setDraft({ ...draft, material: event.target.value })}
          placeholder="Cotton, merino wool, leather"
          type="text"
          value={draft.material}
        />
      </label>

      <label className="form-field">
        <span>Notes</span>
        <textarea
          onChange={(event) => setDraft({ ...draft, notes: event.target.value })}
          rows={3}
          value={draft.notes}
        />
      </label>

      {error ? <p className="error-message">{error}</p> : null}

      <button type="submit" className="secondary-button" disabled={isSaving}>
        {isSaving ? <span className="spinner small" aria-hidden="true" /> : <Save size={20} />}
        Save Item and Rescore
      </button>
    </form>
  )
}

function clothingItemDraftFromItem(item: ClothingItem): ClothingItemDraft {
  return {
    name: item.name,
    brand: item.brand,
    category: item.category,
    quantity: item.quantity,
    color: item.color,
    material: item.material,
    pattern: item.pattern,
    notes: item.notes,
    imageBase64: item.imageBase64,
    imageMimeType: item.imageMimeType,
    status: item.status,
  }
}

function recommendationFromDailyOutfit(
  dailyOutfit: DailyOutfit,
  closetItems: ClothingItem[],
  weather: WeatherInput,
  profile: UserProfile | null,
): OutfitRecommendation | null {
  const selectedItems = dailyOutfit.itemIDs
    .map((itemId) => closetItems.find((item) => item.id === itemId))
    .filter((item): item is ClothingItem => Boolean(item))

  if (selectedItems.length === 0) {
    return null
  }

  const rescoredRecommendation = scoreCustomOutfit({
    context: dailyOutfit.context,
    items: selectedItems,
    profile,
    source: dailyOutfit.source,
    weather,
  })

  return {
    ...rescoredRecommendation,
    id: `daily-${dailyOutfit.date}`,
    rationale: dailyOutfit.rationale || 'Saved outfit for today.',
  }
}

function numberInput(value: string, fallback: number) {
  const parsed = Number.parseInt(value, 10)
  return Number.isFinite(parsed) ? parsed : fallback
}

function quantityInputValue(value: string) {
  if (value.trim() === '') {
    return 0
  }

  const parsed = Number.parseInt(value, 10)
  return Number.isFinite(parsed) ? Math.max(0, parsed) : 0
}

function scoreClass(score: number) {
  if (score >= 75) return 'strong'
  if (score >= 60) return 'usable'
  return 'weak'
}
