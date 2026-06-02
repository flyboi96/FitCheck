import { useMemo, useState } from 'react'
import {
  AlertTriangle,
  Bot,
  CheckCircle2,
  CloudSun,
  MessageSquare,
  RefreshCw,
  Sparkles,
  ThumbsDown,
  ThumbsUp,
  Wand2,
} from 'lucide-react'
import { useClosetItems } from '../hooks/useClosetItems'
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

  async function handleGenerate(askAIFirst: boolean) {
    setIsGenerating(true)
    setGenerationError(null)
    setFeedbackMessage(null)
    setFeedbackError(null)

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
          onFeedback={(type) => {
            void handleFeedback(type)
          }}
          onNoteChange={setFeedbackNote}
          recommendation={recommendation}
          weather={weather}
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
  onFeedback,
  onNoteChange,
  recommendation,
  weather,
}: {
  feedbackError: string | null
  feedbackMessage: string | null
  feedbackNote: string
  isSavingFeedback: boolean
  onFeedback: (type: OutfitFeedbackType) => void
  onNoteChange: (note: string) => void
  recommendation: OutfitRecommendation
  weather: WeatherInput
}) {
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
