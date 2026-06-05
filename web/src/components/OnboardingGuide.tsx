import {
  CheckCircle2,
  Circle,
  CloudSun,
  Image as ImageIcon,
  Shirt,
  Smartphone,
  UserRound,
  Wand2,
  X,
} from 'lucide-react'
import { useState, type ReactNode } from 'react'
import { useClosetItems } from '../hooks/useClosetItems'
import { useSavedAvatar } from '../hooks/useSavedAvatar'
import { getAIProxySettings } from '../lib/settings'
import type { UserProfile } from '../lib/profile'

type SetupStep = {
  actionLabel: string
  description: string
  done: boolean
  icon: ReactNode
  onClick: () => void
  title: string
}

export function OnboardingGuide({
  onComplete,
  onDismiss,
  onOpenAIProxy,
  onOpenAvatar,
  onOpenCloset,
  onOpenProfile,
  onOpenToday,
  profile,
  userId,
}: {
  onComplete: () => void
  onDismiss: () => void
  onOpenAIProxy: () => void
  onOpenAvatar: () => void
  onOpenCloset: () => void
  onOpenProfile: () => void
  onOpenToday: () => void
  profile: UserProfile | null
  userId: string
}) {
  const { items } = useClosetItems(userId)
  const { avatar } = useSavedAvatar(userId)
  const [installInstructionsOpen, setInstallInstructionsOpen] = useState(
    () => !isRunningAsInstalledPWA(),
  )
  const proxySettings = getAIProxySettings()
  const hasProfile =
    Boolean(profile?.displayName.trim()) &&
    profile?.gender !== 'unspecified' &&
    Boolean(profile?.styleDescription.trim())
  const hasCloset = items.some((item) => item.status === 'active')
  const hasAvatar = Boolean(avatar)
  const hasAIProxy = Boolean(proxySettings.proxyUrl.trim()) && Boolean(proxySettings.proxyToken.trim())
  const isInstalled = isRunningAsInstalledPWA()
  const isComplete = hasProfile && hasAIProxy && hasCloset && hasAvatar

  const steps: SetupStep[] = [
    {
      actionLabel: 'How to Install',
      description: 'Add FitCheck to the Home Screen so it opens like a normal app.',
      done: isInstalled,
      icon: <Smartphone size={20} aria-hidden="true" />,
      onClick: () => {
        setInstallInstructionsOpen(true)
        requestAnimationFrame(() => {
          document
            .getElementById('install-fitcheck-instructions')
            ?.scrollIntoView({ behavior: 'smooth', block: 'center' })
        })
      },
      title: 'Install App',
    },
    {
      actionLabel: 'Edit Profile',
      description: 'Add name, gender, style preferences, temperature comfort, dislikes, and rules.',
      done: hasProfile,
      icon: <UserRound size={20} aria-hidden="true" />,
      onClick: onOpenProfile,
      title: 'Personal Profile',
    },
    {
      actionLabel: 'Set AI Proxy',
      description: 'Save your Render proxy URL and token. This keeps the OpenAI key off the phone.',
      done: hasAIProxy,
      icon: <Wand2 size={20} aria-hidden="true" />,
      onClick: onOpenAIProxy,
      title: 'AI Proxy Token',
    },
    {
      actionLabel: 'Add Clothes',
      description: 'Start with bulk import, photo import, or a few key items you wear often.',
      done: hasCloset,
      icon: <Shirt size={20} aria-hidden="true" />,
      onClick: onOpenCloset,
      title: 'Digital Closet',
    },
    {
      actionLabel: 'Save Avatar',
      description: 'Use one full-body reference so outfit previews are faster and more consistent.',
      done: hasAvatar,
      icon: <ImageIcon size={20} aria-hidden="true" />,
      onClick: onOpenAvatar,
      title: 'Avatar',
    },
    {
      actionLabel: 'Try Today',
      description: 'Choose a context, look up full-day weather, then generate and give feedback.',
      done: false,
      icon: <CloudSun size={20} aria-hidden="true" />,
      onClick: onOpenToday,
      title: 'First Outfit',
    },
  ]

  return (
    <section className="onboarding-card" aria-labelledby="setup-guide-title">
      <div className="onboarding-header">
        <div>
          <p className="eyebrow">First-time setup</p>
          <h2 id="setup-guide-title">Get FitCheck Ready</h2>
          <p className="helper-text">
            Install it first, then add your profile, closet, avatar, and AI proxy settings.
          </p>
        </div>
        <button type="button" className="icon-button" onClick={onDismiss} aria-label="Hide setup guide">
          <X size={20} aria-hidden="true" />
        </button>
      </div>

      <details
        className="nested-details"
        id="install-fitcheck-instructions"
        onToggle={(event) => setInstallInstructionsOpen(event.currentTarget.open)}
        open={installInstructionsOpen}
      >
        <summary>Install FitCheck on your Home Screen</summary>
        <div className="install-instructions">
          <div>
            <h3>iPhone or iPad</h3>
            <ol>
              <li>Open the shared FitCheck link in Safari.</li>
              <li>Tap the Share button.</li>
              <li>Choose Add to Home Screen.</li>
              <li>Tap Add, then open FitCheck from the new Home Screen icon.</li>
            </ol>
            <p className="helper-text">
              If Add to Home Screen is missing, open the link in Safari instead of an in-app
              browser, then check the Share sheet again.
            </p>
          </div>
          <div>
            <h3>Android or Desktop</h3>
            <ol>
              <li>Open the shared link in Chrome or Edge.</li>
              <li>Use the browser menu or install icon.</li>
              <li>Choose Install app or Add to Home screen.</li>
            </ol>
          </div>
        </div>
      </details>

      <div className="setup-step-list">
        {steps.map((step) => (
          <button type="button" className="setup-step" key={step.title} onClick={step.onClick}>
            <span className={step.done ? 'setup-step-status done' : 'setup-step-status'}>
              {step.done ? <CheckCircle2 size={20} /> : <Circle size={20} />}
            </span>
            <span className="menu-row-icon">{step.icon}</span>
            <span className="menu-row-content">
              <strong>{step.title}</strong>
              <span>{step.description}</span>
            </span>
            <span className="quantity-chip">{step.done ? 'Done' : step.actionLabel}</span>
          </button>
        ))}
      </div>

      <details className="nested-details">
        <summary>How FitCheck works</summary>
        <ol>
          <li>Your closet is the source. FitCheck only recommends items you actually saved.</li>
          <li>Context sets the purpose: work, travel, casual, lifting, running, and so on.</li>
          <li>Weather adjusts fabric, layers, footwear, and outerwear without changing the context.</li>
          <li>AI proxy improves judgment by applying your profile, closet details, and feedback.</li>
          <li>Liked, rejected, and text feedback improves future recommendations.</li>
        </ol>
      </details>

      <div className="generation-actions">
        <button type="button" className="secondary-button" onClick={onDismiss}>
          Hide Guide
        </button>
        <button type="button" className="primary-button" disabled={!isComplete} onClick={onComplete}>
          <CheckCircle2 size={20} aria-hidden="true" />
          Mark Setup Done
        </button>
      </div>
    </section>
  )
}

function isRunningAsInstalledPWA() {
  if (typeof window === 'undefined') {
    return false
  }

  const standaloneNavigator = window.navigator as Navigator & { standalone?: boolean }
  const isDisplayModeStandalone =
    typeof window.matchMedia === 'function' &&
    window.matchMedia('(display-mode: standalone)').matches

  return isDisplayModeStandalone || standaloneNavigator.standalone === true
}
