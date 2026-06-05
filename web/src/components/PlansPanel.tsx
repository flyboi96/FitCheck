import { type FormEvent, type ReactNode, useMemo, useState } from 'react'
import {
  ArrowLeft,
  ArrowDown,
  ArrowUp,
  CalendarDays,
  ChevronRight,
  Clipboard,
  Copy,
  Download,
  Image as ImageIcon,
  MapPin,
  Plus,
  Save,
  Sparkles,
  Trash2,
  Wand2,
  X,
} from 'lucide-react'
import { ClothingItemBrowser } from './ClothingItemBrowser'
import { useClosetItems } from '../hooks/useClosetItems'
import { useContextStyles } from '../hooks/useContextStyles'
import { usePlans } from '../hooks/usePlans'
import { useSavedAvatar } from '../hooks/useSavedAvatar'
import { generateAvatarPreview, type AvatarPreview } from '../lib/avatar'
import {
  categoryLabel,
  categoryOptionsForWearer,
  clothingStatuses,
  saveClothingItem,
  type ClothingCategory,
  type ClothingItem,
  type ClothingItemDraft,
  type ClothingStatus,
} from '../lib/closet'
import {
  addDaysISO,
  buildPackingList,
  createDaysFromRange,
  createPlanDay,
  createOutfitRequest,
  createPlan,
  dateRangeDayCount,
  defaultNewPlanDraft,
  deletePlan,
  itineraryShareText,
  MAX_EXPANDED_PLAN_DAYS,
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
  defaultWeatherInput,
  generateOutfit,
  scoreCustomOutfit,
  weatherSummary,
  type OutfitContext,
  type OutfitContextOption,
  type OutfitRecommendation,
  type WeatherInput,
} from '../lib/outfits'
import { contextOptionsFromSettings } from '../lib/contextStyles'
import type { UserProfile } from '../lib/profile'
import { lookupWeatherByLocation } from '../lib/weather'

type PlanView = 'home' | 'new' | 'setup' | 'itinerary' | 'packing'

export function PlansPanel({
  profile,
  userId,
}: {
  profile: UserProfile | null
  userId: string
}) {
  const { error: plansError, isLoading: isLoadingPlans, plans } = usePlans(userId)
  const { error: closetError, isLoading: isLoadingCloset, items } = useClosetItems(userId)
  const { settings: contextSettings } = useContextStyles(userId)
  const contextOptions = useMemo(
    () => contextOptionsFromSettings(contextSettings),
    [contextSettings],
  )
  const [selectedPlanId, setSelectedPlanId] = useState('')
  const [newPlanDraft, setNewPlanDraft] = useState<NewPlanDraft>(() => defaultNewPlanDraft())
  const [planDraft, setPlanDraft] = useState<PlanDraft | null>(null)
  const [planView, setPlanView] = useState<PlanView>('home')
  const [isSavingPlan, setIsSavingPlan] = useState(false)
  const [isGenerating, setIsGenerating] = useState(false)
  const [statusMessage, setStatusMessage] = useState<string | null>(null)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [bulkContext, setBulkContext] = useState<OutfitContext>('casual')
  const effectiveBulkContext = contextOptions.some((option) => option.value === bulkContext)
    ? bulkContext
    : contextOptions[0]?.value ?? 'casual'
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

  function openPlan(plan: Plan, view: PlanView = 'setup') {
    setSelectedPlanId(plan.id)
    setPlanDraft(planToDraft(plan))
    setPlanView(view)
    setStatusMessage(null)
    setErrorMessage(null)
  }

  function openNewPlan() {
    setNewPlanDraft(defaultNewPlanDraft())
    setPlanDraft(null)
    setPlanView('new')
    setStatusMessage(null)
    setErrorMessage(null)
  }

  function contextLabel(context: OutfitContext) {
    return contextOptions.find((option) => option.value === context)?.label ?? context
  }

  function newOutfitRequest(context: OutfitContext) {
    const request = createOutfitRequest(context)
    return {
      ...request,
      label: contextLabel(context),
    }
  }

  async function handleCreatePlan(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setIsSavingPlan(true)
    setStatusMessage(null)
    setErrorMessage(null)

    try {
      const planId = await createPlan(userId, newPlanDraft)
      setSelectedPlanId(planId)
      setPlanDraft(null)
      setNewPlanDraft(defaultNewPlanDraft())
      setPlanView('setup')
      setStatusMessage('Plan created with one editable card per day. Adjust locations, weather, and outfit requests below.')
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
      setPlanDraft(null)
      setPlanView('home')
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
      setPlanView('itinerary')
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
      setStatusMessage(`Full-day forecast updated for ${day.date}: ${weatherSummary(nextWeather)}.`)
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
      const nextDays: PlanDay[] = []

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
      const sources = [
        ...new Set(nextDays.map((day) => day.weather.source).filter((source): source is string => Boolean(source))),
      ]
      setStatusMessage(
        `Full-day forecasts updated for ${nextDays.length} day${nextDays.length === 1 ? '' : 's'}${
          sources.length > 0 ? ` via ${sources.join(', ')}` : ''
        }.`,
      )
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
        requests: day.requests.some((request) => request.context === effectiveBulkContext)
          ? day.requests
          : [...day.requests, newOutfitRequest(effectiveBulkContext)],
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
      await saveGeneratedPlan(userId, selectedPlan.id, nextItinerary, buildPackingList(nextItinerary, items))
      setStatusMessage('Itinerary edits saved. Packing list updated.')
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Could not save itinerary edits.'
      setErrorMessage(message)
      throw new Error(message, { cause: error })
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

  const statusBlock = (
    <>
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
    </>
  )

  if (planView === 'new') {
    return (
      <div className="plans-panel">
        <PlanSubpageHeader
          onBack={() => setPlanView('home')}
          subtitle="Plans"
          title="Start Plan"
        />
        {statusBlock}
        <form className="plan-create-card" onSubmit={handleCreatePlan}>
          <div className="section-title">
            <CalendarDays size={20} aria-hidden="true" />
            <div>
              <p className="eyebrow">New plan</p>
              <h2>Dates and first city</h2>
            </div>
          </div>
          <p className="helper-text">
            This creates one editable card per day in the selected range, up to 21 days.
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
                onChange={(event) =>
                  setNewPlanDraft({ ...newPlanDraft, endDate: event.target.value })
                }
                type="date"
                value={newPlanDraft.endDate}
              />
            </label>
          </div>

          <label className="form-field">
            <span>First Location</span>
            <input
              onChange={(event) =>
                setNewPlanDraft({ ...newPlanDraft, location: event.target.value })
              }
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
            Notes are for constraints. They are not parsed as stops.
          </p>

          <button type="submit" className="primary-button" disabled={isSavingPlan}>
            {isSavingPlan ? <span className="spinner small" aria-hidden="true" /> : <Plus size={20} />}
            Create Plan
          </button>
        </form>
      </div>
    )
  }

  if (planView !== 'home' && (!selectedPlan || !effectivePlanDraft)) {
    return (
      <div className="plans-panel">
        <PlanSubpageHeader onBack={() => setPlanView('home')} subtitle="Plans" title="Plan" />
        {statusBlock}
        <div className="empty-state">
          <Clipboard size={24} aria-hidden="true" />
          <h3>Select a plan</h3>
          <p>Choose a plan from the Plans list to edit it.</p>
        </div>
      </div>
    )
  }

  if (planView === 'setup' && selectedPlan && effectivePlanDraft) {
    return (
      <div className="plans-panel">
        <PlanSubpageHeader onBack={() => setPlanView('home')} subtitle="Plans" title={selectedPlan.name} />
        {statusBlock}
        <section className="subpage-list" aria-label="Plan sections">
          <PlanMenuRow
            badge={`${selectedPlan.itinerary.length}`}
            description="Generated day-by-day outfits and outfit edit tools."
            icon={<CalendarDays size={20} aria-hidden="true" />}
            onClick={() => setPlanView('itinerary')}
            title="Itinerary"
          />
          <PlanMenuRow
            badge={`${selectedPlan.packingList.length}`}
            description="Packing list derived from the generated itinerary."
            icon={<Clipboard size={20} aria-hidden="true" />}
            onClick={() => setPlanView('packing')}
            title="Packing List"
          />
        </section>
        <PlanEditor
          activeClosetCount={activeClosetCount}
          bulkContext={effectiveBulkContext}
          bulkLocation={bulkLocation}
          contextOptions={contextOptions}
          createRequest={newOutfitRequest}
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
        <button
          type="button"
          className="danger-button full-width"
          onClick={() => {
            void handleDeletePlan()
          }}
        >
          <Trash2 size={18} aria-hidden="true" />
          Delete Plan
        </button>
      </div>
    )
  }

  if (planView === 'itinerary' && selectedPlan) {
    return (
      <div className="plans-panel">
        <PlanSubpageHeader
          onBack={() => setPlanView('setup')}
          subtitle={selectedPlan.name}
          title="Itinerary"
        />
        {statusBlock}
        <ItinerarySection
          closetItems={items}
          onChange={(nextItinerary) => handleSaveItinerary(nextItinerary)}
          plan={selectedPlan}
          profile={profile}
          userId={userId}
        />
        <button
          type="button"
          className="secondary-button"
          onClick={() => {
            void shareText(`${selectedPlan.name} itinerary`, itineraryShareText(selectedPlan))
          }}
        >
          <Download size={20} aria-hidden="true" />
          Share Itinerary
        </button>
      </div>
    )
  }

  if (planView === 'packing' && selectedPlan) {
    return (
      <div className="plans-panel">
        <PlanSubpageHeader
          onBack={() => setPlanView('setup')}
          subtitle={selectedPlan.name}
          title="Packing List"
        />
        {statusBlock}
        <PackingSection
          closetItems={items}
          groupedPackingList={groupedPackingList}
          onChange={(nextPackingList) => {
            void handleSavePackingList(nextPackingList)
          }}
          plan={selectedPlan}
          profile={profile}
          userId={userId}
        />
        {groupedPackingList.length === 0 ? (
          <div className="empty-state">
            <Clipboard size={24} aria-hidden="true" />
            <h3>No packing list yet</h3>
            <p>Generate the itinerary first. The packing list follows from those outfits.</p>
          </div>
        ) : null}
        <button
          type="button"
          className="secondary-button"
          onClick={() => {
            void shareText(`${selectedPlan.name} packing list`, packingListShareText(selectedPlan))
          }}
        >
          <Copy size={20} aria-hidden="true" />
          Share Packing List
        </button>
      </div>
    )
  }

  return (
    <div className="plans-panel">
      <section className="plan-workspace">
        <div className="section-title">
          <Clipboard size={20} aria-hidden="true" />
          <div>
            <p className="eyebrow">Plans</p>
            <h2>Trips and weekly outfits</h2>
          </div>
        </div>
        <button type="button" className="primary-button" onClick={openNewPlan}>
          <Plus size={20} aria-hidden="true" />
          New Plan
        </button>
        {statusBlock}
        {!isLoadingPlans && plans.length === 0 ? (
          <div className="empty-state">
            <Clipboard size={24} aria-hidden="true" />
            <h3>No plans yet</h3>
            <p>Create a trip or weekly plan, then edit the daily outfit requests.</p>
          </div>
        ) : null}
        {plans.length > 0 ? (
          <section className="subpage-list" aria-label="Saved plans">
            {plans.map((plan) => (
              <PlanMenuRow
                badge={`${plan.days.length}d`}
                description={`${plan.startDate} to ${plan.endDate} - ${plan.itinerary.length} outfits`}
                icon={<CalendarDays size={20} aria-hidden="true" />}
                key={plan.id}
                onClick={() => openPlan(plan)}
                title={plan.name}
              />
            ))}
          </section>
        ) : null}
      </section>
    </div>
  )
}

function PlanSubpageHeader({
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

function PlanMenuRow({
  badge,
  description,
  icon,
  onClick,
  title,
}: {
  badge?: string
  description: string
  icon: ReactNode
  onClick: () => void
  title: string
}) {
  return (
    <button type="button" className="menu-row" onClick={onClick}>
      <span className="menu-row-icon">{icon}</span>
      <span className="menu-row-content">
        <strong>{title}</strong>
        <span>{description}</span>
      </span>
      {badge ? <span className="quantity-chip">{badge}</span> : null}
      <ChevronRight className="menu-row-chevron" size={20} aria-hidden="true" />
    </button>
  )
}

function PlanEditor({
  activeClosetCount,
  bulkContext,
  bulkLocation,
  contextOptions,
  createRequest,
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
  contextOptions: OutfitContextOption[]
  createRequest: (context: OutfitContext) => ReturnType<typeof createOutfitRequest>
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
  const rangeDayCount = dateRangeDayCount(draft.startDate, draft.endDate)
  const cappedRangeCount = Math.min(rangeDayCount, MAX_EXPANDED_PLAN_DAYS)

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
        ...(lastDay?.weather ?? defaultWeatherInput),
        location: lastDay?.location ?? '',
      },
      requests: [createRequest(contextOptions[0]?.value ?? 'casual')],
    }

    onChange({
      ...draft,
      endDate: nextDate,
      days: [...draft.days, nextDay],
    })
  }

  function expandDateRange() {
    if (rangeDayCount > MAX_EXPANDED_PLAN_DAYS) {
      const confirmedLargeRange = window.confirm(
        `This date range has ${rangeDayCount} dates. FitCheck will create the first ${MAX_EXPANDED_PLAN_DAYS} day cards so the editor stays usable. Continue?`,
      )

      if (!confirmedLargeRange) {
        return
      }
    }

    const confirmed =
      draft.days.length <= 1 ||
      window.confirm(
        `Replace the current ${draft.days.length} day card${draft.days.length === 1 ? '' : 's'} with ${cappedRangeCount} card${cappedRangeCount === 1 ? '' : 's'} from ${draft.startDate} to ${draft.endDate}?`,
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

  function collapseToFirstDay() {
    const firstDay = draft.days[0] ?? createPlanDay(draft.startDate, '')

    onChange({
      ...draft,
      startDate: firstDay.date,
      endDate: firstDay.date,
      days: [firstDay],
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
          editable day card{draft.days.length === 1 ? '' : 's'}. The selected date range is{' '}
          {rangeDayCount} day{rangeDayCount === 1 ? '' : 's'}.
        </span>
      </div>

      {draft.days.length > MAX_EXPANDED_PLAN_DAYS ? (
        <div className="plan-warning-card">
          <strong>This plan has {draft.days.length} day cards.</strong>
          <span>
            That is probably from an older range-expansion bug. Collapse it to one day and rebuild
            only the days you actually need.
          </span>
          <button type="button" className="secondary-button" onClick={collapseToFirstDay}>
            Keep First Day Only
          </button>
        </div>
      ) : null}

      <div className="weather-source-card">
        <strong>Plan Weather</strong>
        <span>
          Set the location on each day, then tap Look Up All Weather. FitCheck stores the day-by-day
          forecast on the plan before generating outfits.
        </span>
      </div>

      <div className="plan-flow-card">
        <strong>Flow</strong>
        <span>1. Create or add only the day cards you need.</span>
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
            {contextOptions.map((context) => (
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

      <div className="generation-actions">
        <button type="button" className="secondary-button" onClick={addDay}>
          <Plus size={20} aria-hidden="true" />
          Add One Day
        </button>
        <button type="button" className="secondary-button" onClick={expandDateRange}>
          <CalendarDays size={20} aria-hidden="true" />
          Create Date Cards
        </button>
      </div>
      <p className="helper-text">
        Date cards control the actual itinerary. The top date range is just a label until you
        create cards from it.
      </p>

      <details className="collapsible-card" open={draft.days.length <= 10}>
        <summary>Daily Details ({draft.days.length})</summary>
        <div className="day-list">
          {draft.days.map((day, index) => (
            <PlanDayEditor
              canMoveDown={index < draft.days.length - 1}
              canMoveUp={index > 0}
              contextOptions={contextOptions}
              createRequest={createRequest}
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
  contextOptions,
  createRequest,
  day,
  onChange,
  onLookupWeather,
  onMoveDown,
  onMoveUp,
  onRemove,
}: {
  canMoveDown: boolean
  canMoveUp: boolean
  contextOptions: OutfitContextOption[]
  createRequest: (context: OutfitContext) => ReturnType<typeof createOutfitRequest>
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

  function updateDayTemperature(field: 'highTemperatureF' | 'lowTemperatureF', value: number) {
    const nextWeather = {
      ...day.weather,
      [field]: value,
    }
    const high = nextWeather.highTemperatureF
    const low = nextWeather.lowTemperatureF

    updateWeather({
      ...nextWeather,
      temperatureF: Math.round((high + low) / 2),
      source: 'Manual full-day weather',
    })
  }

  function updateRequest(requestId: string, context: OutfitContext) {
    const contextLabel = contextOptions.find((option) => option.value === context)?.label ?? context

    onChange({
      ...day,
      requests: day.requests.map((request) =>
        request.id === requestId
          ? {
              ...request,
              context,
              label: contextLabel,
            }
          : request,
      ),
    })
  }

  function removeRequest(requestId: string) {
    const nextRequests = day.requests.filter((request) => request.id !== requestId)
    onChange({
      ...day,
      requests:
        nextRequests.length > 0
          ? nextRequests
          : [createRequest(contextOptions[0]?.value ?? 'casual')],
    })
  }

  function optionsForRequest(request: PlanDay['requests'][number]) {
    if (contextOptions.some((context) => context.value === request.context)) {
      return contextOptions
    }

    return [
      {
        value: request.context,
        label: `${request.label || request.context} (removed)`,
        description: 'This context was removed from your current context list.',
      },
      ...contextOptions,
    ]
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
          <span>Day High F</span>
          <input
            onChange={(event) =>
              updateDayTemperature('highTemperatureF', numberInput(event.target.value, 75))
            }
            type="number"
            value={day.weather.highTemperatureF}
          />
        </label>
        <label className="form-field compact">
          <span>Day Low F</span>
          <input
            onChange={(event) =>
              updateDayTemperature('lowTemperatureF', numberInput(event.target.value, 75))
            }
            type="number"
            value={day.weather.lowTemperatureF}
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
        Look Up Full-Day Forecast
      </button>

      <div className="request-list">
        {day.requests.map((request) => (
          <div className="request-row" key={request.id}>
            <select
              onChange={(event) => updateRequest(request.id, event.target.value as OutfitContext)}
              value={request.context}
            >
              {optionsForRequest(request).map((context) => (
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
            requests: [...day.requests, createRequest(contextOptions[0]?.value ?? 'casual')],
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
  closetItems,
  onChange,
  plan,
  profile,
  userId,
}: {
  closetItems: ClothingItem[]
  onChange: (itinerary: Plan['itinerary']) => Promise<void> | void
  plan: Plan
  profile: UserProfile | null
  userId: string
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
            closetItems={closetItems}
            key={outfit.id}
            onChange={(nextOutfit) =>
              onChange(plan.itinerary.map((entry) => (entry.id === outfit.id ? nextOutfit : entry)))
            }
            onRemove={() => onChange(plan.itinerary.filter((entry) => entry.id !== outfit.id))}
            outfit={outfit}
            profile={profile}
            userId={userId}
            weather={weatherForItineraryOutfit(plan, outfit)}
          />
        ))}
      </div>
    </section>
  )
}

function weatherForItineraryOutfit(plan: Plan, outfit: Plan['itinerary'][number]): WeatherInput {
  const matchingDay =
    plan.days.find(
      (day) =>
        day.date === outfit.date &&
        (!outfit.location || day.location === outfit.location || day.weather.location === outfit.location),
    ) ?? plan.days.find((day) => day.date === outfit.date)

  if (!matchingDay) {
    return {
      ...defaultWeatherInput,
      location: outfit.location,
    }
  }

  return {
    ...matchingDay.weather,
    location: outfit.location || matchingDay.location || matchingDay.weather.location,
  }
}

function EditableItineraryCard({
  closetItems,
  onChange,
  onRemove,
  outfit,
  profile,
  userId,
  weather,
}: {
  closetItems: ClothingItem[]
  onChange: (outfit: Plan['itinerary'][number]) => Promise<void> | void
  onRemove: () => void
  outfit: Plan['itinerary'][number]
  profile: UserProfile | null
  userId: string
  weather: WeatherInput
}) {
  const { avatar: savedAvatar } = useSavedAvatar(userId)
  const [date, setDate] = useState(outfit.date)
  const [location, setLocation] = useState(outfit.location)
  const [label, setLabel] = useState(outfit.label)
  const [selectedItemIDs, setSelectedItemIDs] = useState(outfit.itemIDs)
  const [editError, setEditError] = useState<string | null>(null)
  const [editMessage, setEditMessage] = useState<string | null>(null)
  const [isSavingOutfit, setIsSavingOutfit] = useState(false)
  const [avatarPreview, setAvatarPreview] = useState<AvatarPreview | null>(null)
  const [isGeneratingAvatar, setIsGeneratingAvatar] = useState(false)
  const [avatarError, setAvatarError] = useState<string | null>(null)

  const closetItemsById = useMemo(
    () => new Map(closetItems.map((item) => [item.id, item])),
    [closetItems],
  )
  const selectableItems = useMemo(
    () => closetItems.filter((item) => item.status === 'active' || selectedItemIDs.includes(item.id)),
    [closetItems, selectedItemIDs],
  )
  const selectedItems = useMemo(
    () =>
      selectedItemIDs
        .map((itemID) => closetItemsById.get(itemID))
        .filter((item): item is ClothingItem => Boolean(item)),
    [closetItemsById, selectedItemIDs],
  )

  async function saveEdits() {
    const weatherForScore = {
      ...weather,
      location: location || weather.location,
    }

    if (selectedItems.length === 0) {
      setEditMessage(null)
      setEditError('Choose at least one closet item.')
      return
    }

    const rescoredOutfit = scoreCustomOutfit({
      context: outfit.context,
      items: selectedItems,
      profile,
      source: outfit.source,
      weather: weatherForScore,
    })

    setIsSavingOutfit(true)
    setEditError(null)
    setEditMessage('Saving outfit edits...')

    try {
      await onChange({
        ...outfit,
        date,
        location,
        label,
        weatherSummary: weatherSummary(weatherForScore),
        itemIDs: selectedItems.map((item) => item.id),
        itemNames: selectedItems.map((item) => item.name),
        score: rescoredOutfit.score,
        scoreLabel: rescoredOutfit.scoreLabel,
        rationale: 'Edited itinerary outfit rescored from your selected closet items.',
        reasons: rescoredOutfit.reasons,
        cautions: rescoredOutfit.cautions,
      })
      setEditMessage('Outfit saved and score recalculated.')
    } catch (error) {
      setEditMessage(null)
      setEditError(error instanceof Error ? error.message : 'Could not save outfit edits.')
    } finally {
      setIsSavingOutfit(false)
    }
  }

  async function handleAvatarPreview() {
    if (!savedAvatar) {
      setAvatarError('Save a full-body avatar reference in More before generating plan previews.')
      return
    }

    if (selectedItems.length === 0) {
      setAvatarError('Choose outfit items before generating an avatar preview.')
      return
    }

    const recommendation: OutfitRecommendation = {
      id: outfit.id,
      items: selectedItems,
      score: outfit.score,
      scoreLabel: outfit.scoreLabel,
      source: outfit.source,
      rationale: outfit.rationale,
      reasons: outfit.reasons,
      cautions: outfit.cautions,
    }

    setIsGeneratingAvatar(true)
    setAvatarError(null)

    try {
      setAvatarPreview(
        await generateAvatarPreview({
          profile,
          recommendation,
          savedAvatar,
          weather: {
            ...weather,
            location: location || weather.location,
          },
        }),
      )
    } catch (error) {
      setAvatarError(error instanceof Error ? error.message : 'Avatar preview failed.')
    } finally {
      setIsGeneratingAvatar(false)
    }
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
          <span>Closet Items</span>
          <ClothingItemBrowser
            compact
            items={selectableItems}
            onSelectionChange={setSelectedItemIDs}
            selectedItemIDs={selectedItemIDs}
            selectionMode="multiple"
          />
        </label>
        {editMessage ? <p className="success-message">{editMessage}</p> : null}
        {editError ? <p className="error-message">{editError}</p> : null}
        <div className="generation-actions">
          <button type="button" className="danger-button" onClick={onRemove}>
            <Trash2 size={18} aria-hidden="true" />
            Remove Outfit
          </button>
          <button type="button" className="secondary-button" disabled={isSavingOutfit} onClick={() => {
            void saveEdits()
          }}>
            {isSavingOutfit ? <span className="spinner small" aria-hidden="true" /> : <Save size={20} aria-hidden="true" />}
            Save Outfit Edits
          </button>
        </div>
      </details>
      <details>
        <summary>Avatar preview</summary>
        <p className="helper-text">
          Uses your saved full-body avatar from More with this plan outfit and the day weather.
        </p>
        <button
          type="button"
          className="secondary-button"
          disabled={isGeneratingAvatar}
          onClick={() => {
            void handleAvatarPreview()
          }}
        >
          {isGeneratingAvatar ? <span className="spinner small" aria-hidden="true" /> : <ImageIcon size={20} />}
          Generate Plan Avatar
        </button>
        {avatarError ? <p className="error-message">{avatarError}</p> : null}
        {avatarPreview ? (
          <div className="avatar-preview-result">
            <img alt="Generated avatar wearing this planned outfit" src={avatarPreview.imageURL} />
            <p className="helper-text">{avatarPreview.promptSummary}</p>
            <a className="secondary-button" download="fitcheck-plan-avatar.png" href={avatarPreview.imageURL}>
              <Download size={20} aria-hidden="true" />
              Save Image
            </a>
          </div>
        ) : null}
      </details>
    </article>
  )
}

function PackingSection({
  closetItems,
  groupedPackingList,
  onChange,
  plan,
  profile,
  userId,
}: {
  closetItems: ClothingItem[]
  groupedPackingList: Array<[string, Plan['packingList']]>
  onChange: (packingList: Plan['packingList']) => void
  plan: Plan
  profile: UserProfile | null
  userId: string
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
              closetItem={closetItems.find((closetItem) => closetItem.id === item.itemID) ?? null}
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
              profile={profile}
              userId={userId}
            />
          ))}
        </div>
      ))}
    </section>
  )
}

function EditablePackingRow({
  closetItem,
  item,
  onChange,
  onRemove,
  profile,
  userId,
}: {
  closetItem: ClothingItem | null
  item: Plan['packingList'][number]
  onChange: (item: Plan['packingList'][number]) => void
  onRemove: () => void
  profile: UserProfile | null
  userId: string
}) {
  const [packQuantity, setPackQuantity] = useState(item.packQuantity)
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  function savePackingQuantity() {
    setError(null)
    onChange({ ...item, packQuantity })
    setMessage('Packing quantity saved.')
  }

  function handleClosetItemSaved(updatedItem: ClothingItem) {
    onChange({
      ...item,
      availableQuantity: updatedItem.quantity,
      category: updatedItem.category,
      categoryLabel: categoryLabel(updatedItem.category),
      name: updatedItem.name,
    })
    setError(null)
    setMessage(`${updatedItem.name} updated in your closet and this packing list.`)
  }

  return (
    <div className="packing-row editable">
      <div className="packing-item-object">
        <strong>{closetItem?.name ?? item.name}</strong>
        <span>
          {closetItem ? categoryLabel(closetItem.category) : item.categoryLabel}
          {closetItem?.brand ? ` - ${closetItem.brand}` : ''}
          {closetItem?.material ? ` - ${closetItem.material}` : ''}
        </span>
        <span>
          Used {item.useCount}x - available {closetItem?.quantity ?? item.availableQuantity}
        </span>
      </div>

      <div className="packing-edit-actions">
        <label className="form-field compact">
          <span>Pack Qty</span>
          <input
            aria-label="Pack quantity"
            min={0}
            onChange={(event) => setPackQuantity(numberInput(event.target.value, item.packQuantity))}
            type="number"
            value={packQuantity}
          />
        </label>
        <button
          type="button"
          className="secondary-button"
          onClick={savePackingQuantity}
        >
          Save Qty
        </button>
        <button type="button" className="danger-button" onClick={onRemove}>
          Remove
        </button>
      </div>

      {closetItem ? (
        <details className="packing-closet-editor">
          <summary>Edit connected closet item</summary>
          <PackingClosetItemEditor
            item={closetItem}
            onSaved={handleClosetItemSaved}
            profile={profile}
            userId={userId}
          />
        </details>
      ) : (
        <p className="error-message">
          This packing entry no longer matches a closet item. Remove it or regenerate the itinerary.
        </p>
      )}

      {message ? <p className="success-message">{message}</p> : null}
      {error ? <p className="error-message">{error}</p> : null}
    </div>
  )
}

function PackingClosetItemEditor({
  item,
  onSaved,
  profile,
  userId,
}: {
  item: ClothingItem
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
        status: draft.status,
      })
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Could not save closet item.')
    } finally {
      setIsSaving(false)
    }
  }

  return (
    <form className="quick-edit-card" onSubmit={handleSubmit}>
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
              setDraft({ ...draft, quantity: Number.parseInt(event.target.value, 10) || 1 })
            }
            type="number"
            value={draft.quantity}
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
          <span>Material</span>
          <input
            onChange={(event) => setDraft({ ...draft, material: event.target.value })}
            type="text"
            value={draft.material}
          />
        </label>
      </div>

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
        {isSaving ? <span className="spinner small" aria-hidden="true" /> : <Save size={20} aria-hidden="true" />}
        Save Closet Item
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
    status: item.status,
  }
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
