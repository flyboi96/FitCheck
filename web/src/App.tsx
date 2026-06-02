import { useState } from 'react'
import {
  CalendarDays,
  CheckCircle2,
  CloudSun,
  Database,
  MoreHorizontal,
  PackageCheck,
  Shirt,
  Sparkles,
  UserRound,
  Wand2,
} from 'lucide-react'
import './App.css'
import { firebaseStatus } from './lib/firebase'

const tabs = [
  { id: 'today', label: 'Today', icon: CloudSun },
  { id: 'plans', label: 'Plans', icon: CalendarDays },
  { id: 'closet', label: 'Closet', icon: Shirt },
  { id: 'build', label: 'Build', icon: Wand2 },
  { id: 'more', label: 'More', icon: MoreHorizontal },
] as const

type TabID = (typeof tabs)[number]['id']

const phaseCards = [
  {
    title: 'Firebase-ready shell',
    detail: 'Web config is loaded from Vite env variables and ready for Auth/Firestore wiring.',
    icon: Database,
  },
  {
    title: 'Installable PWA',
    detail: 'Vite PWA manifest and service worker are configured for Add to Home Screen.',
    icon: PackageCheck,
  },
  {
    title: 'AI path preserved',
    detail: 'The existing backend proxy remains the place for OpenAI calls and API-key protection.',
    icon: Sparkles,
  },
]

const nextPhases = [
  'pwa-02-auth-firestore: login, user profile, and Firestore reads/writes',
  'pwa-03-closet: closet list, search, add/edit item, quantity',
  'pwa-04-today-build-ai: Ask AI First and local fit display',
  'pwa-05-plans: daily plan, itinerary, packing list, exports',
]

function App() {
  const [activeTab, setActiveTab] = useState<TabID>('today')
  const ActiveIcon = tabs.find((tab) => tab.id === activeTab)?.icon ?? CloudSun

  return (
    <main className="app-shell">
      <section className="top-bar" aria-label="FitCheck PWA status">
        <div>
          <p className="eyebrow">PWA phase 01</p>
          <h1>FitCheck</h1>
        </div>
        <div className={firebaseStatus.isConfigured ? 'status-pill ready' : 'status-pill warning'}>
          {firebaseStatus.isConfigured ? <CheckCircle2 size={18} /> : <Database size={18} />}
          <span>{firebaseStatus.isConfigured ? 'Firebase ready' : 'Firebase env missing'}</span>
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

        <div className="setup-grid" aria-label="Scaffold readiness">
          {phaseCards.map((card) => {
            const Icon = card.icon
            return (
              <article className="setup-card" key={card.title}>
                <Icon size={22} aria-hidden="true" />
                <h3>{card.title}</h3>
                <p>{card.detail}</p>
              </article>
            )
          })}
        </div>

        {!firebaseStatus.isConfigured ? (
          <div className="notice">
            <Database size={18} aria-hidden="true" />
            <p>Missing Firebase env values: {firebaseStatus.missingKeys.join(', ')}</p>
          </div>
        ) : null}
      </section>

      <section className="roadmap" aria-labelledby="roadmap-title">
        <div className="section-title">
          <UserRound size={20} aria-hidden="true" />
          <h2 id="roadmap-title">Next build phases</h2>
        </div>
        <ol>
          {nextPhases.map((phase) => (
            <li key={phase}>{phase}</li>
          ))}
        </ol>
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

export default App
