import { useEffect, useMemo, useRef, useState } from 'react'
import {
  AlertTriangle,
  Bot,
  CalendarCheck,
  CheckCircle2,
  CloudSun,
  Download,
  Image as ImageIcon,
  LocateFixed,
  MapPin,
  MessageSquare,
  RefreshCw,
  Sparkles,
  ThumbsDown,
  ThumbsUp,
  Wand2,
} from 'lucide-react'
import { useClosetItems } from '../hooks/useClosetItems'
import { useSavedAvatar } from '../hooks/useSavedAvatar'
import { generateAvatarPreview, type AvatarPreview } from '../lib/avatar'
import { logOutfitWear } from '../lib/history'
import { categoryName } from '../lib/outfits'
import {
  defaultWeatherInput,
  generateOutfit,
  outfitContexts,
  saveOutfitFeedback,
  weatherSummary,
  type OutfitContext,
  type OutfitFeedbackType,
  type OutfitRecommendation,
  type WeatherInput,
} from '../lib/outfits'
import type { UserProfile } from '../lib/profile'
import { lookupWeatherAtCurrentLocation, lookupWeatherByLocation } from '../lib/weather'

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
  const [context, setContext] = useState<OutfitContext>('work')
  const [weather, setWeather] = useState<WeatherInput>(defaultWeatherInput)
  const [selectedItemId, setSelectedItemId] = useState('')
  const [recommendation, setRecommendation] = useState<OutfitRecommendation | null>(null)
  const [isGenerating, setIsGenerating] = useState(false)
  const [generationError, setGenerationError] = useState<string | null>(null)
  const [feedbackNote, setFeedbackNote] = useState('')
  const [feedbackMessage, setFeedbackMessage] = useState<string | null>(null)
  const [feedbackError, setFeedbackError] = useState<string | null>(null)
  const [isSavingFeedback, setIsSavingFeedback] = useState(false)
  const [isLoggingWear, setIsLoggingWear] = useState(false)
  const [wearLogMessage, setWearLogMessage] = useState<string | null>(null)
  const [wearLogError, setWearLogError] = useState<string | null>(null)
  const [isLookingUpWeather, setIsLookingUpWeather] = useState(false)
  const [weatherStatus, setWeatherStatus] = useState<string | null>(null)
  const [weatherError, setWeatherError] = useState<string | null>(null)
  const autoWeatherAttempted = useRef(false)

  const activeItems = useMemo(() => items.filter((item) => item.status === 'active'), [items])
  const selectedItem = activeItems.find((item) => item.id === selectedItemId)
  const sortedActiveItems = useMemo(
    () =>
      activeItems
        .slice()
        .sort((first, second) =>
          `${categoryName(first.category)} ${first.name}`.localeCompare(
            `${categoryName(second.category)} ${second.name}`,
          ),
        ),
    [activeItems],
  )

  useEffect(() => {
    if (mode !== 'today' || autoWeatherAttempted.current) {
      return
    }

    autoWeatherAttempted.current = true

    const timer = window.setTimeout(() => {
      setIsLookingUpWeather(true)
      setWeatherStatus('Trying current-location weather.')
      setWeatherError(null)

      lookupWeatherAtCurrentLocation()
        .then((nextWeather) => {
          setWeather(nextWeather)
          setWeatherStatus(`Auto weather loaded: ${weatherSummary(nextWeather)}`)
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

  async function handleGenerate(askAIFirst: boolean) {
    setIsGenerating(true)
    setGenerationError(null)
    setFeedbackMessage(null)
    setFeedbackError(null)
    setWearLogMessage(null)
    setWearLogError(null)

    try {
      const nextRecommendation = await generateOutfit({
        askAIFirst,
        closet: items,
        context,
        profile,
        selectedItemId: mode === 'build' ? selectedItemId || undefined : undefined,
        userId,
        weather,
      })
      setRecommendation(nextRecommendation)
    } catch (error) {
      setGenerationError(error instanceof Error ? error.message : 'Could not generate an outfit.')
    } finally {
      setIsGenerating(false)
    }
  }

  async function handleWeatherLookup(useCurrentLocation: boolean) {
    setIsLookingUpWeather(true)
    setWeatherStatus(null)
    setWeatherError(null)

    try {
      const nextWeather = useCurrentLocation
        ? await lookupWeatherAtCurrentLocation()
        : await lookupWeatherByLocation(weather.location)
      setWeather(nextWeather)
      setWeatherStatus(`Weather updated: ${weatherSummary(nextWeather)}`)
    } catch (error) {
      setWeatherError(error instanceof Error ? error.message : 'Weather lookup failed.')
    } finally {
      setIsLookingUpWeather(false)
    }
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
        context,
        feedback: type,
        note: feedbackNote,
        recommendation,
        userId,
        weather,
      })
      setFeedbackMessage('Feedback saved. Future AI requests include recent feedback.')
      setFeedbackNote('')
    } catch (error) {
      setFeedbackError(error instanceof Error ? error.message : 'Could not save feedback.')
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

    try {
      await logOutfitWear({
        context,
        contextLabel: outfitContexts.find((option) => option.value === context)?.label ?? context,
        note,
        recommendation,
        userId,
        weather,
      })
      setWearLogMessage('Wear logged. Rotation data updated.')
    } catch (error) {
      setWearLogError(error instanceof Error ? error.message : 'Could not log wear.')
    } finally {
      setIsLoggingWear(false)
    }
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
              value={context}
            >
              {outfitContexts.map((option) => (
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
          {outfitContexts.find((option) => option.value === context)?.description}
        </p>

        <div className="weather-source-card">
          <strong>Weather Source</strong>
          <span>
            {weather.location.trim()
              ? `${weather.location} - ${weather.temperatureF}F, ${weather.condition}, ${weather.humidityPercent}% humidity`
              : 'Manual weather values until current location or city lookup succeeds.'}
          </span>
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
            Look Up Weather
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
            Use Current
          </button>
        </div>

        {weatherStatus ? <p className="success-message">{weatherStatus}</p> : null}
        {weatherError ? <p className="error-message">{weatherError}</p> : null}

        <div className="weather-grid">
          <label className="form-field">
            <span>Temp F</span>
            <input
              inputMode="numeric"
              onChange={(event) =>
                setWeather({ ...weather, temperatureF: numberInput(event.target.value, 75) })
              }
              type="number"
              value={weather.temperatureF}
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
          <label className="form-field">
            <span>Required Item</span>
            <select
              onChange={(event) => setSelectedItemId(event.target.value)}
              value={selectedItemId}
            >
              <option value="">No required item</option>
              {sortedActiveItems.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.name} - {categoryName(item.category)}
                </option>
              ))}
            </select>
          </label>
        ) : null}

        {mode === 'build' && selectedItem ? (
          <p className="helper-text">Building around: {selectedItem.name}</p>
        ) : null}

        <div className="generation-actions">
          <button
            type="button"
            className="primary-button"
            disabled={isGenerating || activeItems.length === 0}
            onClick={() => {
              void handleGenerate(true)
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
              void handleGenerate(false)
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

      {!isLoading && activeItems.length === 0 ? (
        <div className="empty-state">
          <AlertTriangle size={24} aria-hidden="true" />
          <h3>No active closet items</h3>
          <p>Add active items in Closet before generating outfits.</p>
        </div>
      ) : null}

      {recommendation ? (
        <OutfitResultCard
          feedbackNote={feedbackNote}
          feedbackError={feedbackError}
          feedbackMessage={feedbackMessage}
          isSavingFeedback={isSavingFeedback}
          isLoggingWear={isLoggingWear}
          onFeedback={(type) => {
            void handleFeedback(type)
          }}
          onLogWear={(note) => {
            void handleLogWear(note)
          }}
          onNoteChange={setFeedbackNote}
          profile={profile}
          recommendation={recommendation}
          userId={userId}
          weather={weather}
          wearLogError={wearLogError}
          wearLogMessage={wearLogMessage}
        />
      ) : null}
    </div>
  )
}

function OutfitResultCard({
  feedbackError,
  feedbackMessage,
  feedbackNote,
  isSavingFeedback,
  isLoggingWear,
  onFeedback,
  onLogWear,
  onNoteChange,
  profile,
  recommendation,
  userId,
  weather,
  wearLogError,
  wearLogMessage,
}: {
  feedbackError: string | null
  feedbackMessage: string | null
  feedbackNote: string
  isSavingFeedback: boolean
  isLoggingWear: boolean
  onFeedback: (type: OutfitFeedbackType) => void
  onLogWear: (note: string) => void
  onNoteChange: (note: string) => void
  profile: UserProfile | null
  recommendation: OutfitRecommendation
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
        {recommendation.items.map((item) => (
          <div className="outfit-item-row" key={item.id}>
            <div>
              <strong>{item.name}</strong>
              <span>
                {categoryName(item.category)}
                {item.brand ? ` - ${item.brand}` : ''}
              </span>
            </div>
            <span className="quantity-chip">Qty {item.quantity}</span>
          </div>
        ))}
      </div>

      <div className="wear-log-panel">
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

      <div className="avatar-panel">
        <div className="section-title">
          <ImageIcon size={20} aria-hidden="true" />
          <h3>Avatar Preview</h3>
        </div>
        <p className="helper-text">
          {savedAvatar
            ? 'Using your saved avatar from More. You can still upload a one-time reference photo to override it.'
            : 'Use a full-body reference photo with head, hair, and shoes visible.'}
        </p>
        <label className="form-field">
          <span>Reference Photo</span>
          <input
            accept="image/*"
            capture="user"
            onChange={(event) => setAvatarFile(event.target.files?.[0] ?? null)}
            type="file"
          />
        </label>
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
      </div>

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

        <div className="feedback-actions">
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

function numberInput(value: string, fallback: number) {
  const parsed = Number.parseInt(value, 10)
  return Number.isFinite(parsed) ? parsed : fallback
}

function scoreClass(score: number) {
  if (score >= 70) return 'strong'
  if (score >= 54) return 'usable'
  return 'weak'
}
