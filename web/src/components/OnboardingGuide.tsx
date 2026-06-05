import {
  CheckCircle2,
  Circle,
  CloudSun,
  Image as ImageIcon,
  Shirt,
  UserRound,
  Wand2,
  X,
} from 'lucide-react'
import type { ReactNode } from 'react'
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
  const proxySettings = getAIProxySettings()
  const hasProfile =
    Boolean(profile?.displayName.trim()) &&
    profile?.gender !== 'unspecified' &&
    Boolean(profile?.styleDescription.trim())
  const hasCloset = items.some((item) => item.status === 'active')
  const hasAvatar = Boolean(avatar)
  const hasAIProxy = Boolean(proxySettings.proxyUrl.trim()) && Boolean(proxySettings.proxyToken.trim())
  const isComplete = hasProfile && hasAIProxy && hasCloset && hasAvatar

  const steps: SetupStep[] = [
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
            The outfit quality depends on your profile, real closet, weather, and AI proxy setup.
          </p>
        </div>
        <button type="button" className="icon-button" onClick={onDismiss} aria-label="Hide setup guide">
          <X size={20} aria-hidden="true" />
        </button>
      </div>

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
