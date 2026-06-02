import { type FormEvent, useMemo, useState } from 'react'
import {
  ArrowDown,
  ArrowUp,
  CalendarDays,
  Clipboard,
  Copy,
  Download,
  MapPin,
  Plus,
  Save,
  Sparkles,
  Trash2,
  Wand2,
  X,
} from 'lucide-react'
import { useClosetItems } from '../hooks/useClosetItems'
import { usePlans } from '../hooks/usePlans'
import {
  addDaysISO,
  buildPackingList,
  createDaysFromRange,
  createOutfitRequest,
  createPlan,
  defaultNewPlanDraft,
  deletePlan,
  itineraryShareText,
  packingListShareText,
  recommendationToItineraryOutfit,
  saveGeneratedPlan,
  savePlan,
  todayISO,
  type NewPlanDraft,
  type Plan,
  type PlanDay,
  type PlanDraft,
  type PackingListItem,
} from '../lib/plans'
import {
  generateOutfit,
  outfitContexts,
  type OutfitContext,
  type WeatherInput,
} from '../lib/outfits'
import type { UserProfile } from '../lib/profile'
import { lookupWeatherByLocation } from '../lib/weather'

export function PlansPanel({
  profile,
  userId,
}: {
  profile: UserProfile | null
  userId: string
}) {
  const { error: plansError, isLoading: isLoadingPlans, plans } = usePlans(userId)
  const { error: closetError, isLoading: isLoadingCloset, items } = useClosetItems(userId)
  const [selectedPlanId, setSelectedPlanId] = useState('')
  const [newPlanDraft, setNewPlanDraft] = useState<NewPlanDraft>(() => defaultNewPlanDraft())
  const [planDraft, setPlanDraft] = useState<PlanDraft | null>(null)
  const [isSavingPlan, setIsSavingPlan] = useState(false)
  const [isGenerating, setIsGenerating] = useState(false)
  const [statusMessage, setStatusMessage] = useState<string | null>(null)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [bulkContext, setBulkContext] = useState<OutfitContext>('casual')
  const [bulkLocation, setBulkLocation] = useState('')
  const [isLookingUpWeather, setIsLookingUpWeather] = useState(false)

  const effectiveSelectedPlanId = selectedPlanId || plans[0]?.id || ''
  const selectedPlan = plans.find((plan) => plan.id === effectiveSelectedPlanId) ?? null
  const effectivePlanDraft = planDraft ?? (selectedPlan ? planToDraft(selectedPlan) : null)
  const activeClosetCount = items.filter((item) => item.status === 'active').length

  const groupedPackingList = useMemo(() => {
    const groups = new Map<string, PackingListItem[]>()

    selectedPlan?.packingList.forEach((item) => {
      const existing = groups.get(item.categoryLabel) ?? []
      groups.set(item.categoryLabel, [...existing, item])
    })

    return [...groups.entries()]
  }, [selectedPlan])

  async function handleCreatePlan(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setIsSavingPlan(true)
    setStatusMessage(null)
    setErrorMessage(null)

    try {
      await createPlan(userId, newPlanDraft)
      setNewPlanDraft(defaultNewPlanDraft())
      setStatusMessage('Plan created.')
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Could not create plan.')
    } finally {
      setIsSavingPlan(false)
    }
  }

  async function handleSavePlan() {
    if (!selectedPlan || !effectivePlanDraft) {
      return
    }

    setIsSavingPlan(true)
    setStatusMessage(null)
    setErrorMessage(null)

    try {
      await savePlan(userId, selectedPlan.id, effectivePlanDraft)
      setStatusMessage('Plan saved.')
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Could not save plan.')
    } finally {
      setIsSavingPlan(false)
    }
  }

  async function handleDeletePlan() {
    if (!selectedPlan) {
      return
    }

    const confirmed = window.confirm(`Delete "${selectedPlan.name}"?`)
    if (!confirmed) {
      return
    }

    setStatusMessage(null)
    setErrorMessage(null)

    try {
      await deletePlan(userId, selectedPlan.id)
      setSelectedPlanId('')
      setStatusMessage('Plan deleted.')
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Could not delete plan.')
    }
  }

  async function handleGenerateItinerary(askAIFirst: boolean) {
    if (!selectedPlan || !effectivePlanDraft) {
      return
    }

    setIsGenerating(true)
    setStatusMessage(null)
    setErrorMessage(null)

    try {
      await savePlan(userId, selectedPlan.id, effectivePlanDraft)

      const itinerary = []
      for (const day of effectivePlanDraft.days) {
        for (const request of day.requests) {
          const recommendation = await generateOutfit({
            askAIFirst,
            closet: items,
            context: request.context,
            profile,
            userId,
            weather: {
              ...day.weather,
              location: day.location || day.weather.location,
            },
          })

          itinerary.push(recommendationToItineraryOutfit({ day, recommendation, request }))
        }
      }

      const packingList = buildPackingList(itinerary, items)
      await saveGeneratedPlan(userId, selectedPlan.id, itinerary, packingList)
      setStatusMessage('Itinerary and packing list generated.')
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Could not generate itinerary.')
    } finally {
      setIsGenerating(false)
    }
  }

  async function shareText(title: string, text: string) {
    if (!text.trim()) {
      setErrorMessage('Generate this plan before sharing.')
      return
    }

    try {
      if (navigator.share) {
        await navigator.share({ title, text })
      } else {
        await navigator.clipboard.writeText(text)
        setStatusMessage('Copied to clipboard.')
      }
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Could not share text.')
    }
  }

  function updateDraft(updater: (draft: PlanDraft) => PlanDraft) {
    setPlanDraft((currentDraft) => (currentDraft ? updater(currentDraft) : currentDraft))
  }

  async function lookupWeatherForDay(dayId: string) {
    if (!effectivePlanDraft) {
      return
    }

    const day = effectivePlanDraft.days.find((planDay) => planDay.id === dayId)
    if (!day) {
      return
    }

    setIsLookingUpWeather(true)
    setStatusMessage(null)
    setErrorMessage(null)

    try {
      const nextWeather = await lookupWeatherByLocation(day.location || day.weather.location, day.date)
      updateDraft((draft) => ({
        ...draft,
        days: draft.days.map((planDay) =>
          planDay.id === dayId
            ? {
                ...planDay,
                location: nextWeather.location,
                weather: nextWeather,
              }
            : planDay,
        ),
      }))
      setStatusMessage(`Weather updated for ${day.date}.`)
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Weather lookup failed.')
    } finally {
      setIsLookingUpWeather(false)
    }
  }

  async function lookupWeatherForAllDays() {
    if (!effectivePlanDraft) {
      return
    }

    setIsLookingUpWeather(true)
    setStatusMessage(null)
    setErrorMessage(null)

    try {
      const nextDays = []

      for (const day of effectivePlanDraft.days) {
        const nextWeather = await lookupWeatherByLocation(day.location || day.weather.location, day.date)
        nextDays.push({
          ...day,
          location: nextWeather.location,
          weather: nextWeather,
        })
      }

      setPlanDraft({
        ...effectivePlanDraft,
        days: nextDays,
      })
      setStatusMessage('Weather updated for all plan days.')
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Could not update all weather.')
    } finally {
      setIsLookingUpWeather(false)
    }
  }

  function applyBulkContext() {
    updateDraft((draft) => ({
      ...draft,
      days: draft.days.map((day) => ({
        ...day,
        requests: day.requests.some((request) => request.context === bulkContext)
          ? day.requests
          : [...day.requests, createOutfitRequest(bulkContext)],
      })),
    }))
  }

  function applyBulkLocation() {
    const nextLocation = bulkLocation.trim()
    if (!nextLocation) {
      return
    }

    updateDraft((draft) => ({
      ...draft,
      days: draft.days.map((day) => ({
        ...day,
        location: nextLocation,
        weather: {
          ...day.weather,
          location: nextLocation,
        },
      })),
    }))
  }

  async function handleSaveItinerary(nextItinerary: Plan['itinerary']) {
    if (!selectedPlan) {
      return
    }

    setStatusMessage(null)
    setErrorMessage(null)

    try {
      await saveGeneratedPlan(userId, selectedPlan.id, nextItinerary, selectedPlan.packingList)
      setStatusMessage('Itinerary edits saved. Packing list unchanged.')
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Could not save itinerary edits.')
    }
  }

  async function handleSavePackingList(nextPackingList: Plan['packingList']) {
    if (!selectedPlan) {
      return
    }

    setStatusMessage(null)
    setErrorMessage(null)

    try {
      await saveGeneratedPlan(userId, selectedPlan.id, selectedPlan.itinerary, nextPackingList)
      setStatusMessage('Packing list edits saved.')
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Could not save packing edits.')
    }
  }

  return (
    <div className="plans-panel">
      <form className="plan-create-card" onSubmit={handleCreatePlan}>
        <div className="section-title">
          <CalendarDays size={20} aria-hidden="true" />
          <div>
            <p className="eyebrow">New plan</p>
            <h2>Start Plan</h2>
          </div>
        </div>
        <p className="helper-text">
          This creates one editable day first. Add more days only when you need them, or expand
          the full date range inside the plan editor.
        </p>

        <label className="form-field">
          <span>Plan Name</span>
          <input
            onChange={(event) => setNewPlanDraft({ ...newPlanDraft, name: event.target.value })}
            placeholder="West Africa Week"
            type="text"
            value={newPlanDraft.name}
          />
        </label>

        <div className="two-column-fields">
          <label className="form-field">
            <span>Start</span>
            <input
              onChange={(event) =>
                setNewPlanDraft({ ...newPlanDraft, startDate: event.target.value })
              }
              type="date"
              value={newPlanDraft.startDate}
            />
          </label>

          <label className="form-field">
            <span>End</span>
            <input
              min={newPlanDraft.startDate}
              onChange={(event) => setNewPlanDraft({ ...newPlanDraft, endDate: event.target.value })}
              type="date"
              value={newPlanDraft.endDate}
            />
          </label>
        </div>

        <label className="form-field">
          <span>First Location</span>
          <input
            onChange={(event) => setNewPlanDraft({ ...newPlanDraft, location: event.target.value })}
            placeholder="Djibouti"
            type="text"
            value={newPlanDraft.location}
          />
        </label>
        <p className="helper-text">
          Use one city here, such as `Djibouti` or `Katy, TX`. Add other cities on individual
          days after the plan is created.
        </p>

        <label className="form-field">
          <span>Notes</span>
          <textarea
            onChange={(event) => setNewPlanDraft({ ...newPlanDraft, notes: event.target.value })}
            placeholder="Work days, dinners, exercise goals, laundry, or packing constraints."
            rows={3}
            value={newPlanDraft.notes}
          />
        </label>
        <p className="helper-text">
          Notes are for constraints: work days, dinners, exercise goals, laundry, or packing
          preferences. They are not parsed as stops.
        </p>

        <button type="submit" className="primary-button" disabled={isSavingPlan}>
          {isSavingPlan ? <span className="spinner small" aria-hidden="true" /> : <Plus size={20} />}
          Create Plan
        </button>
      </form>

      <div className="plan-workspace">
        <div className="plan-selector-row">
          <label className="form-field compact">
            <span>Current Plan</span>
            <select
              onChange={(event) => {
                const nextPlanId = event.target.value
                const nextPlan = plans.find((plan) => plan.id === nextPlanId)
                setSelectedPlanId(nextPlanId)
                setPlanDraft(nextPlan ? planToDraft(nextPlan) : null)
              }}
              value={selectedPlan?.id ?? ''}
            >
              {plans.map((plan) => (
                <option key={plan.id} value={plan.id}>
                  {plan.name}
                </option>
              ))}
            </select>
          </label>
          <button
            type="button"
            className="danger-button"
            disabled={!selectedPlan}
            onClick={() => {
              void handleDeletePlan()
            }}
          >
            <Trash2 size={18} aria-hidden="true" />
            Delete
          </button>
        </div>

        {isLoadingPlans || isLoadingCloset ? (
          <div className="placeholder-panel">
            <span className="spinner small" aria-hidden="true" />
            <div>
              <h3>Loading plans</h3>
              <p>Reading plans and closet items from Firestore.</p>
            </div>
          </div>
        ) : null}

        {plansError || closetError || errorMessage ? (
          <p className="error-message">{plansError ?? closetError ?? errorMessage}</p>
        ) : null}
        {statusMessage ? <p className="success-message">{statusMessage}</p> : null}

        {!isLoadingPlans && plans.length === 0 ? (
          <div className="empty-state">
            <Clipboard size={24} aria-hidden="true" />
            <h3>No plans yet</h3>
            <p>Create a trip or weekly plan, then edit the daily outfit requests.</p>
          </div>
        ) : null}

        {selectedPlan && effectivePlanDraft ? (
          <>
            <PlanEditor
              activeClosetCount={activeClosetCount}
              bulkContext={bulkContext}
              bulkLocation={bulkLocation}
              draft={effectivePlanDraft}
              isGenerating={isGenerating}
              isLookingUpWeather={isLookingUpWeather}
              isSavingPlan={isSavingPlan}
              onAddBulkContext={applyBulkContext}
              onApplyBulkLocation={applyBulkLocation}
              onBulkContextChange={setBulkContext}
              onBulkLocationChange={setBulkLocation}
              onChange={setPlanDraft}
              onGenerateAI={() => {
                void handleGenerateItinerary(true)
              }}
              onGenerateLocal={() => {
                void handleGenerateItinerary(false)
              }}
              onLookupAllWeather={() => {
                void lookupWeatherForAllDays()
              }}
              onLookupDayWeather={(dayId) => {
                void lookupWeatherForDay(dayId)
              }}
              onSave={() => {
                void handleSavePlan()
              }}
            />

            <ItinerarySection
              onChange={(nextItinerary) => {
                void handleSaveItinerary(nextItinerary)
              }}
              plan={selectedPlan}
            />
            <PackingSection
              groupedPackingList={groupedPackingList}
              onChange={(nextPackingList) => {
                void handleSavePackingList(nextPackingList)
              }}
              plan={selectedPlan}
            />

            <div className="share-actions">
              <button
                type="button"
                className="secondary-button"
                onClick={() => {
                  void shareText(
                    `${selectedPlan.name} itinerary`,
                    itineraryShareText(selectedPlan),
                  )
                }}
              >
                <Download size={20} aria-hidden="true" />
                Share Itinerary
              </button>
              <button
                type="button"
                className="secondary-button"
                onClick={() => {
                  void shareText(
                    `${selectedPlan.name} packing list`,
                    packingListShareText(selectedPlan),
                  )
                }}
              >
                <Copy size={20} aria-hidden="true" />
                Share Packing List
              </button>
            </div>
          </>
        ) : null}
      </div>
    </div>
  )
}

function PlanEditor({
  activeClosetCount,
  bulkContext,
  bulkLocation,
  draft,
  isGenerating,
  isLookingUpWeather,
  isSavingPlan,
  onAddBulkContext,
  onApplyBulkLocation,
  onBulkContextChange,
  onBulkLocationChange,
  onChange,
  onGenerateAI,
  onGenerateLocal,
  onLookupAllWeather,
  onLookupDayWeather,
  onSave,
}: {
  activeClosetCount: number
  bulkContext: OutfitContext
  bulkLocation: string
  draft: PlanDraft
  isGenerating: boolean
  isLookingUpWeather: boolean
  isSavingPlan: boolean
  onAddBulkContext: () => void
  onApplyBulkLocation: () => void
  onBulkContextChange: (context: OutfitContext) => void
  onBulkLocationChange: (location: string) => void
  onChange: (draft: PlanDraft) => void
  onGenerateAI: () => void
  onGenerateLocal: () => void
  onLookupAllWeather: () => void
  onLookupDayWeather: (dayId: string) => void
  onSave: () => void
}) {
  function updateDay(dayId: string, updater: (day: PlanDay) => PlanDay) {
    onChange({
      ...draft,
      days: draft.days.map((day) => (day.id === dayId ? updater(day) : day)),
    })
  }

  function moveDay(dayId: string, direction: -1 | 1) {
    const currentIndex = draft.days.findIndex((day) => day.id === dayId)
    const nextIndex = currentIndex + direction

    if (currentIndex < 0 || nextIndex < 0 || nextIndex >= draft.days.length) {
      return
    }

    const nextDays = draft.days.slice()
    const [movedDay] = nextDays.splice(currentIndex, 1)
    nextDays.splice(nextIndex, 0, movedDay)
    onChange({
      ...draft,
      days: nextDays,
    })
  }

  function addDay() {
    const lastDay = draft.days[draft.days.length - 1]
    const nextDate = addDaysISO(lastDay?.date ?? draft.endDate ?? todayISO(), 1)
    const nextDay: PlanDay = {
      id: crypto.randomUUID(),
      date: nextDate,
      location: lastDay?.location ?? '',
      weather: {
        ...(lastDay?.weather ?? {
          location: '',
          temperatureF: 75,
          condition: 'Clear',
          isRaining: false,
          humidityPercent: 45,
          windMph: 5,
        }),
        location: lastDay?.location ?? '',
      },
      requests: [createOutfitRequest('casual')],
    }

    onChange({
      ...draft,
      endDate: nextDate,
      days: [...draft.days, nextDay],
    })
  }

  function expandDateRange() {
    const confirmed =
      draft.days.length <= 1 ||
      window.confirm(
        `Replace the current ${draft.days.length} day card${draft.days.length === 1 ? '' : 's'} with one card for every date from ${draft.startDate} to ${draft.endDate}?`,
      )

    if (!confirmed) {
      return
    }

    onChange({
      ...draft,
      days: createDaysFromRange({
        startDate: draft.startDate,
        endDate: draft.endDate,
        location: draft.days[0]?.location ?? '',
      }),
    })
  }

  function removeDay(dayId: string) {
    const nextDays = draft.days.filter((day) => day.id !== dayId)
    onChange({
      ...draft,
      days: nextDays,
      startDate: nextDays[0]?.date ?? draft.startDate,
      endDate: nextDays[nextDays.length - 1]?.date ?? draft.endDate,
    })
  }

  return (
    <div className="plan-editor-card">
      <div className="section-title">
        <Clipboard size={20} aria-hidden="true" />
        <div>
          <p className="eyebrow">Daily plan</p>
          <h2>{draft.name}</h2>
        </div>
      </div>

      <label className="form-field">
        <span>Plan Name</span>
        <input
          onChange={(event) => onChange({ ...draft, name: event.target.value })}
          type="text"
          value={draft.name}
        />
      </label>

      <div className="two-column-fields">
        <label className="form-field compact">
          <span>Start</span>
          <input
            onChange={(event) => onChange({ ...draft, startDate: event.target.value })}
            type="date"
            value={draft.startDate}
          />
        </label>
        <label className="form-field compact">
          <span>End</span>
          <input
            min={draft.startDate}
            onChange={(event) => onChange({ ...draft, endDate: event.target.value })}
            type="date"
            value={draft.endDate}
          />
        </label>
      </div>

      <div className="plan-summary-card">
        <strong>{draft.days.length}</strong>
        <span>
          editable day card{draft.days.length === 1 ? '' : 's'} for {draft.startDate} to{' '}
          {draft.endDate}
        </span>
      </div>

      <div className="weather-source-card">
        <strong>Plan Weather</strong>
        <span>
          Set the location on each day, then tap Look Up All Weather. FitCheck stores the day-by-day
          forecast on the plan before generating outfits.
        </span>
      </div>

      <div className="plan-flow-card">
        <strong>Flow</strong>
        <span>1. Set days and outfit requests.</span>
        <span>2. Look up weather.</span>
        <span>3. Generate itinerary.</span>
        <span>4. Packing list is derived from the itinerary, then you can edit it.</span>
      </div>

      <label className="form-field">
        <span>Plan Notes</span>
        <textarea
          onChange={(event) => onChange({ ...draft, notes: event.target.value })}
          rows={3}
          value={draft.notes}
        />
      </label>

      <div className="bulk-tools">
        <label className="form-field compact">
          <span>Add outfit to all days</span>
          <select
            onChange={(event) => onBulkContextChange(event.target.value as OutfitContext)}
            value={bulkContext}
          >
            {outfitContexts.map((context) => (
              <option key={context.value} value={context.value}>
                {context.label}
              </option>
            ))}
          </select>
        </label>
        <button type="button" className="secondary-button" onClick={onAddBulkContext}>
          <Plus size={20} aria-hidden="true" />
          Add to All
        </button>

        <label className="form-field compact">
          <span>Set all locations</span>
          <input
            onChange={(event) => onBulkLocationChange(event.target.value)}
            placeholder="Rome"
            type="text"
            value={bulkLocation}
          />
        </label>
        <button type="button" className="secondary-button" onClick={onApplyBulkLocation}>
          <Save size={20} aria-hidden="true" />
          Apply
        </button>
      </div>

      <details className="collapsible-card" open={draft.days.length <= 10}>
        <summary>Daily Details ({draft.days.length})</summary>
        <div className="day-list">
          {draft.days.map((day, index) => (
            <PlanDayEditor
              canMoveDown={index < draft.days.length - 1}
              canMoveUp={index > 0}
              day={day}
              key={day.id}
              onChange={(nextDay) => updateDay(day.id, () => nextDay)}
              onLookupWeather={() => onLookupDayWeather(day.id)}
              onMoveDown={() => moveDay(day.id, 1)}
              onMoveUp={() => moveDay(day.id, -1)}
              onRemove={() => removeDay(day.id)}
            />
          ))}
        </div>
      </details>

      <div className="generation-actions">
        <button type="button" className="secondary-button" onClick={addDay}>
          <Plus size={20} aria-hidden="true" />
          Add One Day
        </button>
        <button type="button" className="secondary-button" onClick={expandDateRange}>
          <CalendarDays size={20} aria-hidden="true" />
          Expand Date Range
        </button>
      </div>

      <div className="generation-actions">
        <button
          type="button"
          className="secondary-button"
          disabled={isLookingUpWeather}
          onClick={onLookupAllWeather}
        >
          {isLookingUpWeather ? <span className="spinner small" aria-hidden="true" /> : <MapPin size={20} />}
          Look Up All Weather
        </button>
        <button type="button" className="secondary-button" disabled={isSavingPlan} onClick={onSave}>
          {isSavingPlan ? <span className="spinner small" aria-hidden="true" /> : <Save size={20} />}
          Save Plan
        </button>
        <button
          type="button"
          className="secondary-button"
          disabled={isGenerating || activeClosetCount === 0}
          onClick={onGenerateLocal}
        >
          <Wand2 size={20} aria-hidden="true" />
          Local Itinerary
        </button>
        <button
          type="button"
          className="primary-button"
          disabled={isGenerating || activeClosetCount === 0}
          onClick={onGenerateAI}
        >
          {isGenerating ? <span className="spinner small" aria-hidden="true" /> : <Sparkles size={20} />}
          AI Itinerary
        </button>
      </div>
    </div>
  )
}

function planToDraft(plan: Plan): PlanDraft {
  return {
    name: plan.name,
    startDate: plan.startDate,
    endDate: plan.endDate,
    notes: plan.notes,
    days: plan.days,
  }
}

function PlanDayEditor({
  canMoveDown,
  canMoveUp,
  day,
  onChange,
  onLookupWeather,
  onMoveDown,
  onMoveUp,
  onRemove,
}: {
  canMoveDown: boolean
  canMoveUp: boolean
  day: PlanDay
  onChange: (day: PlanDay) => void
  onLookupWeather: () => void
  onMoveDown: () => void
  onMoveUp: () => void
  onRemove: () => void
}) {
  function updateWeather(weather: WeatherInput) {
    onChange({ ...day, weather })
  }

  function updateRequest(requestId: string, context: OutfitContext) {
    onChange({
      ...day,
      requests: day.requests.map((request) =>
        request.id === requestId
          ? {
              ...request,
              context,
              label: outfitContexts.find((option) => option.value === context)?.label ?? context,
            }
          : request,
      ),
    })
  }

  function removeRequest(requestId: string) {
    const nextRequests = day.requests.filter((request) => request.id !== requestId)
    onChange({
      ...day,
      requests: nextRequests.length > 0 ? nextRequests : [createOutfitRequest('casual')],
    })
  }

  return (
    <article className="day-card">
      <div className="day-card-header">
        <div>
          <p className="eyebrow">{day.date}</p>
          <h3>{day.location || 'Location TBD'}</h3>
        </div>
        <div className="compact-icon-actions">
          <button
            type="button"
            className="icon-button"
            disabled={!canMoveUp}
            onClick={onMoveUp}
            aria-label="Move day up"
          >
            <ArrowUp size={18} />
          </button>
          <button
            type="button"
            className="icon-button"
            disabled={!canMoveDown}
            onClick={onMoveDown}
            aria-label="Move day down"
          >
            <ArrowDown size={18} />
          </button>
          <button type="button" className="icon-button" onClick={onRemove} aria-label="Remove day">
            <X size={20} />
          </button>
        </div>
      </div>

      <div className="two-column-fields">
        <label className="form-field compact">
          <span>Date</span>
          <input
            onChange={(event) => onChange({ ...day, date: event.target.value })}
            type="date"
            value={day.date}
          />
        </label>
        <label className="form-field compact">
          <span>Location</span>
          <input
            onChange={(event) =>
              onChange({
                ...day,
                location: event.target.value,
                weather: {
                  ...day.weather,
                  location: event.target.value,
                },
              })
            }
            type="text"
            value={day.location}
          />
        </label>
      </div>

      <div className="weather-grid">
        <label className="form-field compact">
          <span>Temp F</span>
          <input
            onChange={(event) =>
              updateWeather({
                ...day.weather,
                temperatureF: numberInput(event.target.value, 75),
              })
            }
            type="number"
            value={day.weather.temperatureF}
          />
        </label>
        <label className="form-field compact">
          <span>Condition</span>
          <input
            onChange={(event) =>
              updateWeather({
                ...day.weather,
                condition: event.target.value,
              })
            }
            type="text"
            value={day.weather.condition}
          />
        </label>
        <label className="form-field compact">
          <span>Humidity</span>
          <input
            onChange={(event) =>
              updateWeather({
                ...day.weather,
                humidityPercent: numberInput(event.target.value, 45),
              })
            }
            type="number"
            value={day.weather.humidityPercent}
          />
        </label>
        <label className="form-field compact">
          <span>Wind</span>
          <input
            onChange={(event) =>
              updateWeather({
                ...day.weather,
                windMph: numberInput(event.target.value, 5),
              })
            }
            type="number"
            value={day.weather.windMph}
          />
        </label>
      </div>

      <label className="toggle-row">
        <input
          checked={day.weather.isRaining}
          onChange={(event) =>
            updateWeather({
              ...day.weather,
              isRaining: event.target.checked,
            })
          }
          type="checkbox"
        />
        <span>Rain or storm risk</span>
      </label>

      <button type="button" className="secondary-button" onClick={onLookupWeather}>
        <MapPin size={20} aria-hidden="true" />
        Look Up Weather
      </button>

      <div className="request-list">
        {day.requests.map((request) => (
          <div className="request-row" key={request.id}>
            <select
              onChange={(event) => updateRequest(request.id, event.target.value as OutfitContext)}
              value={request.context}
            >
              {outfitContexts.map((context) => (
                <option key={context.value} value={context.value}>
                  {context.label}
                </option>
              ))}
            </select>
            <button
              type="button"
              className="icon-button"
              onClick={() => removeRequest(request.id)}
              aria-label="Remove outfit request"
            >
              <X size={18} />
            </button>
          </div>
        ))}
      </div>

      <button
        type="button"
        className="secondary-button"
        onClick={() =>
          onChange({
            ...day,
            requests: [...day.requests, createOutfitRequest('casual')],
          })
        }
      >
        <Plus size={20} aria-hidden="true" />
        Add Outfit Request
      </button>
    </article>
  )
}

function ItinerarySection({
  onChange,
  plan,
}: {
  onChange: (itinerary: Plan['itinerary']) => void
  plan: Plan
}) {
  if (plan.itinerary.length === 0) {
    return (
      <div className="empty-state">
        <CalendarDays size={24} aria-hidden="true" />
        <h3>No itinerary generated</h3>
        <p>Save the daily plan, then generate a local or AI itinerary.</p>
      </div>
    )
  }

  return (
    <section className="generated-section" aria-labelledby="itinerary-heading">
      <div className="section-title">
        <CalendarDays size={20} aria-hidden="true" />
        <h2 id="itinerary-heading">Generated Itinerary</h2>
      </div>
      <div className="itinerary-list">
        {plan.itinerary.map((outfit) => (
          <EditableItineraryCard
            key={outfit.id}
            onChange={(nextOutfit) =>
              onChange(plan.itinerary.map((entry) => (entry.id === outfit.id ? nextOutfit : entry)))
            }
            onRemove={() => onChange(plan.itinerary.filter((entry) => entry.id !== outfit.id))}
            outfit={outfit}
          />
        ))}
      </div>
    </section>
  )
}

function EditableItineraryCard({
  onChange,
  onRemove,
  outfit,
}: {
  onChange: (outfit: Plan['itinerary'][number]) => void
  onRemove: () => void
  outfit: Plan['itinerary'][number]
}) {
  const [date, setDate] = useState(outfit.date)
  const [location, setLocation] = useState(outfit.location)
  const [label, setLabel] = useState(outfit.label)
  const [itemNamesText, setItemNamesText] = useState(outfit.itemNames.join('\n'))

  function saveEdits() {
    const itemNames = itemNamesText
      .split(/\r?\n/)
      .map((itemName) => itemName.trim())
      .filter(Boolean)

    onChange({
      ...outfit,
      date,
      location,
      label,
      itemNames,
    })
  }

  return (
    <article className="itinerary-card">
      <div className="recommendation-header">
        <div>
          <p className="eyebrow">
            {outfit.date} - {outfit.location || 'Location TBD'}
          </p>
          <h3>{outfit.label}</h3>
          <p className="helper-text">{outfit.weatherSummary}</p>
        </div>
        <div className={`score-badge ${scoreClass(outfit.score)}`}>
          <strong>{outfit.score}</strong>
          <span>{outfit.scoreLabel}</span>
        </div>
      </div>
      <ul>
        {outfit.itemNames.map((itemName) => (
          <li key={itemName}>{itemName}</li>
        ))}
      </ul>
      <details>
        <summary>Why this scored this way</summary>
        <p>{outfit.rationale}</p>
        {outfit.reasons.map((reason) => (
          <p key={reason}>{reason}</p>
        ))}
        {outfit.cautions.map((caution) => (
          <p key={caution}>Watch-out: {caution}</p>
        ))}
      </details>
      <details>
        <summary>Edit this outfit</summary>
        <div className="two-column-fields">
          <label className="form-field compact">
            <span>Date</span>
            <input onChange={(event) => setDate(event.target.value)} type="date" value={date} />
          </label>
          <label className="form-field compact">
            <span>Location</span>
            <input onChange={(event) => setLocation(event.target.value)} type="text" value={location} />
          </label>
        </div>
        <label className="form-field compact">
          <span>Label</span>
          <input onChange={(event) => setLabel(event.target.value)} type="text" value={label} />
        </label>
        <label className="form-field">
          <span>Items, one per line</span>
          <textarea
            onChange={(event) => setItemNamesText(event.target.value)}
            rows={5}
            value={itemNamesText}
          />
        </label>
        <div className="generation-actions">
          <button type="button" className="danger-button" onClick={onRemove}>
            <Trash2 size={18} aria-hidden="true" />
            Remove Outfit
          </button>
          <button type="button" className="secondary-button" onClick={saveEdits}>
            <Save size={20} aria-hidden="true" />
            Save Outfit Edits
          </button>
        </div>
      </details>
    </article>
  )
}

function PackingSection({
  groupedPackingList,
  onChange,
  plan,
}: {
  groupedPackingList: Array<[string, Plan['packingList']]>
  onChange: (packingList: Plan['packingList']) => void
  plan: Plan
}) {
  if (groupedPackingList.length === 0) {
    return null
  }

  return (
    <section className="generated-section" aria-labelledby="packing-heading">
      <div className="section-title">
        <Clipboard size={20} aria-hidden="true" />
        <h2 id="packing-heading">Packing List</h2>
      </div>

      {groupedPackingList.map(([category, items]) => (
        <div className="packing-category" key={category}>
          <h3>{category}</h3>
          {items.map((item) => (
            <EditablePackingRow
              item={item}
              key={item.itemID}
              onChange={(nextItem) =>
                onChange(
                  plan.packingList.map((entry) =>
                    entry.itemID === item.itemID ? nextItem : entry,
                  ),
                )
              }
              onRemove={() =>
                onChange(plan.packingList.filter((entry) => entry.itemID !== item.itemID))
              }
            />
          ))}
        </div>
      ))}
    </section>
  )
}

function EditablePackingRow({
  item,
  onChange,
  onRemove,
}: {
  item: Plan['packingList'][number]
  onChange: (item: Plan['packingList'][number]) => void
  onRemove: () => void
}) {
  const [name, setName] = useState(item.name)
  const [packQuantity, setPackQuantity] = useState(item.packQuantity)

  return (
    <div className="packing-row editable">
      <div>
        <input
          aria-label="Packing item name"
          onChange={(event) => setName(event.target.value)}
          type="text"
          value={name}
        />
        <span>
          Used {item.useCount}x - available {item.availableQuantity}
        </span>
      </div>
      <div className="packing-edit-actions">
        <input
          aria-label="Pack quantity"
          min={0}
          onChange={(event) => setPackQuantity(numberInput(event.target.value, item.packQuantity))}
          type="number"
          value={packQuantity}
        />
        <button
          type="button"
          className="secondary-button"
          onClick={() => onChange({ ...item, name, packQuantity })}
        >
          Save
        </button>
        <button type="button" className="danger-button" onClick={onRemove}>
          Remove
        </button>
      </div>
    </div>
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
