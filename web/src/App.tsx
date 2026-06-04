import { lazy, Suspense, type FormEvent, type ReactNode, useState } from 'react'
import {
  createUserWithEmailAndPassword,
  signInWithEmailAndPassword,
  signOut,
  updateProfile,
  type User,
} from 'firebase/auth'
import {
  ArrowLeft,
  CalendarDays,
  CheckCircle2,
  ChevronRight,
  CloudSun,
  Database,
  Eye,
  EyeOff,
  LogOut,
  Mail,
  MoreHorizontal,
  Save,
  Shirt,
  UserRound,
  Wand2,
} from 'lucide-react'
import './App.css'
import { useAuthProfile } from './hooks/useAuthProfile'
import { auth, firebaseStatus } from './lib/firebase'
import {
  emptyUserProfileDraft,
  temperatureSensitivityLabel,
  upsertUserProfile,
  type UserProfile,
  type UserProfileDraft,
  type WearerProfile,
} from './lib/profile'

const LazyAIProxySettingsPanel = lazy(() =>
  import('./components/AIProxySettingsPanel').then((module) => ({
    default: module.AIProxySettingsPanel,
  })),
)
const LazyClosetPanel = lazy(() =>
  import('./components/ClosetPanel').then((module) => ({
    default: module.ClosetPanel,
  })),
)
const LazyOutfitExperiencePanel = lazy(() =>
  import('./components/OutfitExperiencePanel').then((module) => ({
    default: module.OutfitExperiencePanel,
  })),
)
const LazyPlansPanel = lazy(() =>
  import('./components/PlansPanel').then((module) => ({
    default: module.PlansPanel,
  })),
)
const LazyAvatarStudioPanel = lazy(() =>
  import('./components/AvatarStudioPanel').then((module) => ({
    default: module.AvatarStudioPanel,
  })),
)
const LazyDataPortabilityPanel = lazy(() =>
  import('./components/DataPortabilityPanel').then((module) => ({
    default: module.DataPortabilityPanel,
  })),
)
const LazyHistoryPanel = lazy(() =>
  import('./components/HistoryPanel').then((module) => ({
    default: module.HistoryPanel,
  })),
)
const LazyContextStyleEditorPanel = lazy(() =>
  import('./components/ScoringAndContextPanel').then((module) => ({
    default: module.ContextStyleEditorPanel,
  })),
)
const LazyScoringGuidePanel = lazy(() =>
  import('./components/ScoringAndContextPanel').then((module) => ({
    default: module.ScoringGuidePanel,
  })),
)

const tabs = [
  { id: 'today', label: 'Today', icon: CloudSun },
  { id: 'plans', label: 'Plans', icon: CalendarDays },
  { id: 'closet', label: 'Closet', icon: Shirt },
  { id: 'build', label: 'Build', icon: Wand2 },
  { id: 'more', label: 'More', icon: MoreHorizontal },
] as const

type TabID = (typeof tabs)[number]['id']
type AuthMode = 'signIn' | 'register'
type MoreRoute =
  | 'menu'
  | 'profile'
  | 'avatar'
  | 'history'
  | 'backup'
  | 'scoring'
  | 'contexts'
  | 'ai'
  | 'offline'

const wearerOptions: Array<{ value: WearerProfile; label: string }> = [
  { value: 'unspecified', label: 'Unspecified' },
  { value: 'male', label: 'Male' },
  { value: 'female', label: 'Female' },
]

const defaultProfileDraft: UserProfileDraft = emptyUserProfileDraft()

function App() {
  const authState = useAuthProfile()

  if (!firebaseStatus.isConfigured) {
    return <ConfigurationMissing />
  }

  if (authState.isLoading) {
    return <LoadingScreen />
  }

  if (!authState.user) {
    return <AuthGate />
  }

  return (
    <AuthenticatedShell
      error={authState.error}
      profile={authState.profile}
      refreshProfile={authState.refreshProfile}
      user={authState.user}
    />
  )
}

function ConfigurationMissing() {
  return (
    <main className="app-shell centered">
      <section className="auth-card">
        <div className="panel-heading">
          <Database size={28} aria-hidden="true" />
          <div>
            <p className="eyebrow">Configuration needed</p>
            <h1>FitCheck</h1>
          </div>
        </div>
        <div className="notice">
          <Database size={18} aria-hidden="true" />
          <p>Missing Firebase env values: {firebaseStatus.missingKeys.join(', ')}</p>
        </div>
        <p className="helper-text">
          Add the missing `VITE_FIREBASE_*` values in `web/.env.local` for local
          development and as GitHub Actions secrets for GitHub Pages.
        </p>
      </section>
    </main>
  )
}

function LoadingScreen() {
  return (
    <main className="app-shell centered">
      <section className="auth-card loading-card">
        <div className="spinner" aria-hidden="true" />
        <h1>FitCheck</h1>
        <p className="helper-text">Checking your Firebase session.</p>
      </section>
    </main>
  )
}

function AuthGate() {
  const [authMode, setAuthMode] = useState<AuthMode>('signIn')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [draft, setDraft] = useState<UserProfileDraft>(defaultProfileDraft)
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const isRegistering = authMode === 'register'
  const canSubmit = email.trim().length > 0 && password.length >= 6 && !isSubmitting

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()

    if (!auth || !canSubmit) {
      return
    }

    setError(null)
    setIsSubmitting(true)

    try {
      if (isRegistering) {
        const credential = await createUserWithEmailAndPassword(auth, email.trim(), password)
        const displayName = draft.displayName.trim()

        if (displayName) {
          await updateProfile(credential.user, { displayName })
        }

        await upsertUserProfile(credential.user, {
          ...draft,
          displayName,
        })
      } else {
        await signInWithEmailAndPassword(auth, email.trim(), password)
      }
    } catch (authError) {
      setError(friendlyAuthError(authError))
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <main className="app-shell centered">
      <section className="auth-card" aria-labelledby="auth-title">
        <div className="panel-heading">
          <UserRound size={28} aria-hidden="true" />
          <div>
            <p className="eyebrow">PWA phase 07</p>
            <h1 id="auth-title">FitCheck</h1>
          </div>
        </div>

        <div className="segmented-control" role="tablist" aria-label="Authentication mode">
          <button
            type="button"
            className={authMode === 'signIn' ? 'selected' : ''}
            onClick={() => setAuthMode('signIn')}
          >
            Sign in
          </button>
          <button
            type="button"
            className={authMode === 'register' ? 'selected' : ''}
            onClick={() => setAuthMode('register')}
          >
            Register
          </button>
        </div>

        <form className="form-stack" onSubmit={handleSubmit}>
          <label className="form-field">
            <span>Email</span>
            <input
              autoComplete="email"
              inputMode="email"
              onChange={(event) => setEmail(event.target.value)}
              placeholder="you@example.com"
              type="email"
              value={email}
            />
          </label>

          <label className="form-field">
            <span>Password</span>
            <div className="password-row">
              <input
                autoComplete={isRegistering ? 'new-password' : 'current-password'}
                onChange={(event) => setPassword(event.target.value)}
                placeholder="At least 6 characters"
                type={showPassword ? 'text' : 'password'}
                value={password}
              />
              <button
                type="button"
                className="icon-button"
                onClick={() => setShowPassword((current) => !current)}
                aria-label={showPassword ? 'Hide password' : 'Show password'}
              >
                {showPassword ? <EyeOff size={20} /> : <Eye size={20} />}
              </button>
            </div>
          </label>

          {isRegistering ? <ProfileFields compact draft={draft} setDraft={setDraft} /> : null}

          {error ? <p className="error-message">{error}</p> : null}

          <button type="submit" className="primary-button" disabled={!canSubmit}>
            {isSubmitting ? <span className="spinner small" aria-hidden="true" /> : <Mail size={20} />}
            {isRegistering ? 'Create Account' : 'Sign In'}
          </button>
        </form>
      </section>
    </main>
  )
}

function AuthenticatedShell({
  error,
  profile,
  refreshProfile,
  user,
}: {
  error: string | null
  profile: UserProfile | null
  refreshProfile: () => Promise<void>
  user: User
}) {
  const [activeTab, setActiveTab] = useState<TabID>('today')
  const ActiveIcon = tabs.find((tab) => tab.id === activeTab)?.icon ?? CloudSun
  const displayName = profile?.displayName || user.displayName || 'FitCheck user'
  const profileSummary = profile
    ? `${genderLabel(profile.gender)} profile${profile.styleDescription ? ' - style notes saved' : ''}`
    : 'Profile loading'

  return (
    <main className="app-shell">
      <section className="top-bar" aria-label="FitCheck PWA status">
        <div>
          <p className="eyebrow">PWA phase 07</p>
          <h1>FitCheck</h1>
        </div>
        <div className="status-pill ready">
          <CheckCircle2 size={18} />
          <span>Signed in</span>
        </div>
      </section>

      <section className="active-panel" aria-labelledby="active-tab-title">
        <div className="panel-heading">
          <ActiveIcon size={28} aria-hidden="true" />
          <div>
            <p className="eyebrow">Current section</p>
            <h2 id="active-tab-title">{tabs.find((tab) => tab.id === activeTab)?.label}</h2>
          </div>
        </div>

        <div className="account-strip">
          <UserRound size={22} aria-hidden="true" />
          <div>
            <strong>{displayName}</strong>
            <span>{profileSummary}</span>
          </div>
        </div>

        {error ? (
          <div className="notice">
            <Database size={18} aria-hidden="true" />
            <p>{error}</p>
          </div>
        ) : null}

        <Suspense fallback={<TabPanelFallback label={tabs.find((tab) => tab.id === activeTab)?.label ?? 'Tab'} />}>
          {renderTabPanel(activeTab, user, profile, refreshProfile)}
        </Suspense>
      </section>

      <nav className="tab-bar" aria-label="FitCheck sections">
        {tabs.map((tab) => {
          const Icon = tab.icon
          const isActive = activeTab === tab.id
          return (
            <button
              type="button"
              className={isActive ? 'tab active' : 'tab'}
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              aria-current={isActive ? 'page' : undefined}
            >
              <Icon size={24} aria-hidden="true" />
              <span>{tab.label}</span>
            </button>
          )
        })}
      </nav>
    </main>
  )
}

function renderTabPanel(
  activeTab: TabID,
  user: User,
  profile: UserProfile | null,
  refreshProfile: () => Promise<void>,
) {
  switch (activeTab) {
    case 'today':
      return <LazyOutfitExperiencePanel mode="today" profile={profile} userId={user.uid} />
    case 'plans':
      return <LazyPlansPanel profile={profile} userId={user.uid} />
    case 'closet':
      return <LazyClosetPanel userId={user.uid} wearerProfile={profile?.gender ?? 'unspecified'} />
    case 'build':
      return <LazyOutfitExperiencePanel mode="build" profile={profile} userId={user.uid} />
    case 'more':
      return <MorePanel profile={profile} refreshProfile={refreshProfile} user={user} />
  }
}

function TabPanelFallback({ label }: { label: string }) {
  return (
    <div className="placeholder-panel">
      <span className="spinner small" aria-hidden="true" />
      <div>
        <h3>Loading {label}</h3>
        <p>Preparing this section.</p>
      </div>
    </div>
  )
}

function MorePanel({
  profile,
  refreshProfile,
  user,
}: {
  profile: UserProfile | null
  refreshProfile: () => Promise<void>
  user: User
}) {
  const [route, setRoute] = useState<MoreRoute>('menu')

  if (route !== 'menu') {
    return (
      <div className="tab-content">
        <SubpageHeader onBack={() => setRoute('menu')} title={moreRouteTitle(route)} />
        {route === 'profile' ? (
          <ProfileEditor profile={profile} refreshProfile={refreshProfile} user={user} />
        ) : null}
        {route === 'avatar' ? (
          <LazyMoreSection>
            <LazyAvatarStudioPanel profile={profile} userId={user.uid} />
          </LazyMoreSection>
        ) : null}
        {route === 'history' ? (
          <LazyMoreSection>
            <LazyHistoryPanel userId={user.uid} />
          </LazyMoreSection>
        ) : null}
        {route === 'backup' ? (
          <LazyMoreSection>
            <LazyDataPortabilityPanel userId={user.uid} />
          </LazyMoreSection>
        ) : null}
        {route === 'scoring' ? (
          <LazyMoreSection>
            <LazyScoringGuidePanel />
          </LazyMoreSection>
        ) : null}
        {route === 'contexts' ? (
          <LazyMoreSection>
            <LazyContextStyleEditorPanel userId={user.uid} />
          </LazyMoreSection>
        ) : null}
        {route === 'ai' ? (
          <LazyMoreSection>
            <LazyAIProxySettingsPanel />
          </LazyMoreSection>
        ) : null}
        {route === 'offline' ? <OfflineCachePanel /> : null}
      </div>
    )
  }

  return (
    <div className="tab-content">
      <section className="subpage-list" aria-label="More tools">
        <MenuRow
          description="Name, gender, style profile, comfort, and rules."
          icon={<UserRound size={20} aria-hidden="true" />}
          onClick={() => setRoute('profile')}
          title="Profile"
        />
        <MenuRow
          description="Save one full-body avatar for faster outfit previews."
          icon={<Wand2 size={20} aria-hidden="true" />}
          onClick={() => setRoute('avatar')}
          title="Avatar Studio"
        />
        <MenuRow
          description="Logged outfits, item wear counts, and cleanup."
          icon={<CalendarDays size={20} aria-hidden="true" />}
          onClick={() => setRoute('history')}
          title="Outfit History"
        />
        <MenuRow
          description="Export or restore closet, profile, plans, history, and avatar metadata."
          icon={<Database size={20} aria-hidden="true" />}
          onClick={() => setRoute('backup')}
          title="Backup / Import"
        />
        <MenuRow
          description="How FitCheck scores weather, fashion, rotation, and preferences."
          icon={<CheckCircle2 size={20} aria-hidden="true" />}
          onClick={() => setRoute('scoring')}
          title="Scoring Guide"
        />
        <MenuRow
          description="Edit business casual, gym, travel day, and other outfit definitions."
          icon={<Shirt size={20} aria-hidden="true" />}
          onClick={() => setRoute('contexts')}
          title="Context Styles"
        />
        <MenuRow
          description="OpenAI proxy URL and token settings."
          icon={<Wand2 size={20} aria-hidden="true" />}
          onClick={() => setRoute('ai')}
          title="AI Proxy"
        />
        <MenuRow
          description="Firestore cache status and weak-connection behavior."
          icon={<Database size={20} aria-hidden="true" />}
          onClick={() => setRoute('offline')}
          title="Offline Cache"
        />
      </section>
      <button
        type="button"
        className="secondary-button"
        onClick={() => {
          if (auth) {
            void signOut(auth)
          }
        }}
      >
        <LogOut size={20} aria-hidden="true" />
        Sign Out
      </button>
    </div>
  )
}

function SubpageHeader({
  onBack,
  subtitle,
  title,
}: {
  onBack: () => void
  subtitle?: string
  title: string
}) {
  return (
    <div className="subpage-header">
      <button type="button" className="icon-button" onClick={onBack} aria-label="Back">
        <ArrowLeft size={22} />
      </button>
      <div>
        <p className="eyebrow">{subtitle ?? 'Back'}</p>
        <h2>{title}</h2>
      </div>
    </div>
  )
}

function MenuRow({
  description,
  icon,
  onClick,
  title,
}: {
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
      <ChevronRight className="menu-row-chevron" size={20} aria-hidden="true" />
    </button>
  )
}

function OfflineCachePanel() {
  return (
    <section className="profile-form">
      <div className="section-title">
        <Database size={20} aria-hidden="true" />
        <div>
          <p className="eyebrow">Offline</p>
          <h2>Offline Cache</h2>
        </div>
      </div>
      <p className="helper-text">
        Firestore local persistence is enabled. Recently opened closet, profile, plans, history,
        avatar, and context data can continue loading when the connection is weak.
      </p>
    </section>
  )
}

function moreRouteTitle(route: Exclude<MoreRoute, 'menu'>) {
  switch (route) {
    case 'profile':
      return 'Profile'
    case 'avatar':
      return 'Avatar Studio'
    case 'history':
      return 'Outfit History'
    case 'backup':
      return 'Backup / Import'
    case 'scoring':
      return 'Scoring Guide'
    case 'contexts':
      return 'Context Styles'
    case 'ai':
      return 'AI Proxy'
    case 'offline':
      return 'Offline Cache'
  }
}

function LazyMoreSection({ children }: { children: ReactNode }) {
  return <Suspense fallback={<MoreSectionFallback />}>{children}</Suspense>
}

function MoreSectionFallback() {
  return (
    <section className="profile-form">
      <p className="helper-text">
        <span className="spinner small" aria-hidden="true" /> Loading More section.
      </p>
    </section>
  )
}

function ProfileEditor({
  profile,
  refreshProfile,
  user,
}: {
  profile: UserProfile | null
  refreshProfile: () => Promise<void>
  user: User
}) {
  const [draft, setDraft] = useState<UserProfileDraft>(() => ({
    displayName: profile?.displayName ?? user.displayName ?? '',
    gender: profile?.gender ?? 'unspecified',
    styleDescription: profile?.styleDescription ?? '',
    favoriteLooks: profile?.favoriteLooks ?? '',
    preferredColors: profile?.preferredColors ?? '',
    preferredFit: profile?.preferredFit ?? '',
    temperatureSensitivity: profile?.temperatureSensitivity ?? 'neutral',
    statementPiecePreference: profile?.statementPiecePreference ?? '',
    dislikedCombinations: profile?.dislikedCombinations ?? '',
    rules: profile?.rules ?? '',
  }))
  const [styleAnswers, setStyleAnswers] = useState('')
  const [isBuildingStyleProfile, setIsBuildingStyleProfile] = useState(false)
  const [isSaving, setIsSaving] = useState(false)
  const [status, setStatus] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function handleBuildStyleProfile() {
    if (!styleAnswers.trim()) {
      setError('Answer the style questions first.')
      return
    }

    setIsBuildingStyleProfile(true)
    setStatus(null)
    setError(null)

    try {
      const { buildStyleProfileFromAnswers } = await import('./lib/styleCoach')
      const styleDraft = await buildStyleProfileFromAnswers({
        answers: styleAnswers,
        currentDraft: draft,
        profile,
      })
      setDraft({ ...draft, ...styleDraft })
      setStatus('AI drafted your style profile. Review it, then save.')
    } catch (styleError) {
      setError(styleError instanceof Error ? styleError.message : 'Could not build style profile.')
    } finally {
      setIsBuildingStyleProfile(false)
    }
  }

  async function handleSave(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setIsSaving(true)
    setStatus(null)
    setError(null)

    try {
      const displayName = draft.displayName.trim()
      await updateProfile(user, { displayName: displayName || null })
      await upsertUserProfile(user, {
        ...draft,
        displayName,
      })
      await refreshProfile()
      setStatus('Profile saved to Firestore.')
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Could not save profile.')
    } finally {
      setIsSaving(false)
    }
  }

  return (
    <form className="profile-form" onSubmit={handleSave}>
      <div>
        <p className="eyebrow">Account</p>
        <h2>Profile</h2>
        <p className="helper-text">{user.email}</p>
      </div>

      <div className="style-coach-card">
        <div className="section-title">
          <Wand2 size={20} aria-hidden="true" />
          <div>
            <p className="eyebrow">AI Style Coach</p>
            <h3>Build Profile from Answers</h3>
          </div>
        </div>

        <details className="nested-details">
          <summary>Questions to answer</summary>
          <ul>
            <li>What outfits make you feel most like yourself?</li>
            <li>What do you wear most often now?</li>
            <li>What colors, fits, brands, and materials do you usually like?</li>
            <li>Do you run hot or cold compared with other people?</li>
            <li>How often should one bold item show up?</li>
            <li>What feels too flashy, too formal, too casual, or just wrong?</li>
            <li>Are there any hard rules FitCheck should follow?</li>
          </ul>
        </details>

        <label className="form-field">
          <span>Your Answers</span>
          <textarea
            onChange={(event) => setStyleAnswers(event.target.value)}
            placeholder="Example: I usually wear business casual, run hot, like merino/cotton, dislike shorts with boots, and want one bold item occasionally."
            rows={5}
            value={styleAnswers}
          />
        </label>

        <button
          type="button"
          className="secondary-button"
          disabled={isBuildingStyleProfile}
          onClick={() => {
            void handleBuildStyleProfile()
          }}
        >
          {isBuildingStyleProfile ? (
            <span className="spinner small" aria-hidden="true" />
          ) : (
            <Wand2 size={20} aria-hidden="true" />
          )}
          Build Profile from Answers
        </button>
      </div>

      <ProfileFields draft={draft} setDraft={setDraft} />

      {status ? <p className="success-message">{status}</p> : null}
      {error ? <p className="error-message">{error}</p> : null}

      <button type="submit" className="primary-button" disabled={isSaving}>
        {isSaving ? <span className="spinner small" aria-hidden="true" /> : <Save size={20} />}
        Save Profile
      </button>
    </form>
  )
}

function ProfileFields({
  compact = false,
  draft,
  setDraft,
}: {
  compact?: boolean
  draft: UserProfileDraft
  setDraft: (draft: UserProfileDraft) => void
}) {
  return (
    <>
      <label className="form-field">
        <span>Name</span>
        <input
          autoComplete="name"
          onChange={(event) => setDraft({ ...draft, displayName: event.target.value })}
          placeholder="Alex"
          type="text"
          value={draft.displayName}
        />
      </label>

      <label className="form-field">
        <span>Gender/Profile</span>
        <select
          onChange={(event) =>
            setDraft({ ...draft, gender: event.target.value as WearerProfile })
          }
          value={draft.gender}
        >
          {wearerOptions.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
      </label>

      <label className="form-field">
        <span>Style Summary</span>
        <textarea
          onChange={(event) => setDraft({ ...draft, styleDescription: event.target.value })}
          placeholder="Business casual most days, runs hot, dislikes shorts with boots, wants bold pieces occasionally."
          rows={5}
          value={draft.styleDescription}
        />
      </label>

      {compact ? null : (
        <>
          <label className="form-field">
            <span>Favorite Looks</span>
            <textarea
              onChange={(event) => setDraft({ ...draft, favoriteLooks: event.target.value })}
              placeholder="Looks you want FitCheck to aim for."
              rows={4}
              value={draft.favoriteLooks}
            />
          </label>

          <div className="two-column-fields">
            <label className="form-field">
              <span>Preferred Colors</span>
              <input
                onChange={(event) => setDraft({ ...draft, preferredColors: event.target.value })}
                placeholder="Navy, white, khaki, olive"
                type="text"
                value={draft.preferredColors}
              />
            </label>

            <label className="form-field">
              <span>Preferred Fit</span>
              <input
                onChange={(event) => setDraft({ ...draft, preferredFit: event.target.value })}
                placeholder="Trim but not tight"
                type="text"
                value={draft.preferredFit}
              />
            </label>
          </div>

          <label className="form-field">
            <span>Temperature Comfort</span>
            <select
              onChange={(event) =>
                setDraft({
                  ...draft,
                  temperatureSensitivity: event.target.value as UserProfileDraft['temperatureSensitivity'],
                })
              }
              value={draft.temperatureSensitivity}
            >
              {(['runs_hot', 'neutral', 'runs_cold'] as const).map((option) => (
                <option key={option} value={option}>
                  {temperatureSensitivityLabel(option)}
                </option>
              ))}
            </select>
          </label>

          <label className="form-field">
            <span>Statement Pieces</span>
            <textarea
              onChange={(event) =>
                setDraft({ ...draft, statementPiecePreference: event.target.value })
              }
              placeholder="How often bold items should appear and how to balance them."
              rows={3}
              value={draft.statementPiecePreference}
            />
          </label>

          <label className="form-field">
            <span>Disliked Combinations</span>
            <textarea
              onChange={(event) =>
                setDraft({ ...draft, dislikedCombinations: event.target.value })
              }
              placeholder="Shorts with boots, sweatpants for work, colors that clash for you."
              rows={4}
              value={draft.dislikedCombinations}
            />
          </label>

          <label className="form-field">
            <span>Personal Rules</span>
            <textarea
              onChange={(event) => setDraft({ ...draft, rules: event.target.value })}
              placeholder="Example: collared shirts need a belt with belt-loop pants."
              rows={4}
              value={draft.rules}
            />
          </label>
        </>
      )}
    </>
  )
}

function genderLabel(gender: WearerProfile) {
  return wearerOptions.find((option) => option.value === gender)?.label ?? 'Unspecified'
}

function friendlyAuthError(error: unknown) {
  if (!(error instanceof Error)) {
    return 'Authentication failed.'
  }

  if (error.message.includes('auth/invalid-credential')) {
    return 'Email or password is incorrect.'
  }

  if (error.message.includes('auth/email-already-in-use')) {
    return 'That email already has an account. Sign in instead.'
  }

  if (error.message.includes('auth/weak-password')) {
    return 'Password must be at least 6 characters.'
  }

  return error.message
}

export default App
