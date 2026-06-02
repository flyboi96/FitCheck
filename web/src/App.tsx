import { type FormEvent, useState } from 'react'
import {
  createUserWithEmailAndPassword,
  signInWithEmailAndPassword,
  signOut,
  updateProfile,
  type User,
} from 'firebase/auth'
import {
  CalendarDays,
  CheckCircle2,
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
import { AIProxySettingsPanel } from './components/AIProxySettingsPanel'
import { ClosetPanel } from './components/ClosetPanel'
import { OutfitExperiencePanel } from './components/OutfitExperiencePanel'
import { PlansPanel } from './components/PlansPanel'
import { useAuthProfile } from './hooks/useAuthProfile'
import { auth, firebaseStatus } from './lib/firebase'
import {
  upsertUserProfile,
  type UserProfile,
  type UserProfileDraft,
  type WearerProfile,
} from './lib/profile'

const tabs = [
  { id: 'today', label: 'Today', icon: CloudSun },
  { id: 'plans', label: 'Plans', icon: CalendarDays },
  { id: 'closet', label: 'Closet', icon: Shirt },
  { id: 'build', label: 'Build', icon: Wand2 },
  { id: 'more', label: 'More', icon: MoreHorizontal },
] as const

type TabID = (typeof tabs)[number]['id']
type AuthMode = 'signIn' | 'register'

const wearerOptions: Array<{ value: WearerProfile; label: string }> = [
  { value: 'unspecified', label: 'Unspecified' },
  { value: 'male', label: 'Male' },
  { value: 'female', label: 'Female' },
]

const defaultProfileDraft: UserProfileDraft = {
  displayName: '',
  gender: 'unspecified',
  styleDescription: '',
}

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
          displayName,
          gender: draft.gender,
          styleDescription: draft.styleDescription,
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
            <p className="eyebrow">PWA phase 05</p>
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

          {isRegistering ? <ProfileFields draft={draft} setDraft={setDraft} /> : null}

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
          <p className="eyebrow">PWA phase 05</p>
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

        {renderTabPanel(activeTab, user, profile, refreshProfile)}
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
      return <OutfitExperiencePanel mode="today" profile={profile} userId={user.uid} />
    case 'plans':
      return <PlansPanel profile={profile} userId={user.uid} />
    case 'closet':
      return <ClosetPanel userId={user.uid} wearerProfile={profile?.gender ?? 'unspecified'} />
    case 'build':
      return <OutfitExperiencePanel mode="build" profile={profile} userId={user.uid} />
    case 'more':
      return <MorePanel profile={profile} refreshProfile={refreshProfile} user={user} />
  }
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
  return (
    <div className="tab-content">
      <ProfileEditor profile={profile} refreshProfile={refreshProfile} user={user} />
      <AIProxySettingsPanel />
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
  }))
  const [isSaving, setIsSaving] = useState(false)
  const [status, setStatus] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

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
  draft,
  setDraft,
}: {
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
        <span>Style Preferences</span>
        <textarea
          onChange={(event) => setDraft({ ...draft, styleDescription: event.target.value })}
          placeholder="Business casual most days, runs hot, dislikes shorts with boots, wants bold pieces occasionally."
          rows={5}
          value={draft.styleDescription}
        />
      </label>
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
