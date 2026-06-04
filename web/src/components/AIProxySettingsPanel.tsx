import { type FormEvent, useState } from 'react'
import { RefreshCw, Save, ShieldCheck } from 'lucide-react'
import { getAIProxySettings, saveAIProxySettings, type AIProxySettings } from '../lib/settings'

export function AIProxySettingsPanel() {
  const [settings, setSettings] = useState<AIProxySettings>(() => getAIProxySettings())
  const [status, setStatus] = useState<string | null>(null)
  const [testStatus, setTestStatus] = useState<string | null>(null)
  const [testError, setTestError] = useState<string | null>(null)
  const [isTesting, setIsTesting] = useState(false)

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    saveAIProxySettings(settings)
    setStatus('AI proxy settings saved on this device.')
  }

  async function handleTestProxy() {
    setIsTesting(true)
    setStatus(null)
    setTestStatus(null)
    setTestError(null)
    saveAIProxySettings(settings)

    try {
      const baseURL = normalizedProxyURL(settings.proxyUrl)
      const configurationProblem = proxyURLConfigurationProblem(baseURL)

      if (configurationProblem) {
        throw new Error(configurationProblem)
      }

      const health = await fetch(`${baseURL}/health`)

      if (!health.ok) {
        throw new Error(`Proxy health check returned HTTP ${health.status}.`)
      }

      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
      }

      if (settings.proxyToken.trim()) {
        headers['X-FitCheck-Token'] = settings.proxyToken.trim()
      }

      const weather = await fetch(`${baseURL}/weather-lookup`, {
        body: JSON.stringify({
          date: new Date().toISOString().slice(0, 10),
          location: 'Djibouti',
        }),
        headers,
        method: 'POST',
      })
      const payload = (await weather.json().catch(() => ({}))) as { error?: string; location?: string }

      if (!weather.ok) {
        if (weather.status === 404) {
          throw new Error('Proxy is reachable, but /weather-lookup was not found. Redeploy the Render backend.')
        }

        if (weather.status === 401) {
          throw new Error('Proxy is reachable, but the proxy token is invalid or missing.')
        }

        throw new Error(payload.error || `Weather proxy returned HTTP ${weather.status}.`)
      }

      setTestStatus(`Proxy and weather lookup work. Test location: ${payload.location || 'Djibouti'}.`)
    } catch (error) {
      setTestError(error instanceof Error ? error.message : 'Proxy test failed.')
    } finally {
      setIsTesting(false)
    }
  }

  return (
    <form className="profile-form" onSubmit={handleSubmit}>
      <div className="section-title">
        <ShieldCheck size={20} aria-hidden="true" />
        <div>
          <p className="eyebrow">AI</p>
          <h2>Proxy Settings</h2>
        </div>
      </div>

      <p className="helper-text">
        The OpenAI API key stays in Render. This browser only stores the proxy URL and optional
        proxy token needed to call your backend.
      </p>

      <label className="form-field">
        <span>Proxy URL</span>
        <input
          onChange={(event) => setSettings({ ...settings, proxyUrl: event.target.value })}
          placeholder="https://your-fitcheck-api.onrender.com"
          type="url"
          value={settings.proxyUrl}
        />
      </label>

      <label className="form-field">
        <span>Proxy Token</span>
        <input
          onChange={(event) => setSettings({ ...settings, proxyToken: event.target.value })}
          placeholder="Optional FITCHECK_PROXY_TOKEN"
          type="password"
          value={settings.proxyToken}
        />
      </label>

      {status ? <p className="success-message">{status}</p> : null}
      {testStatus ? <p className="success-message">{testStatus}</p> : null}
      {testError ? <p className="error-message">{testError}</p> : null}

      <div className="generation-actions">
        <button type="submit" className="secondary-button">
          <Save size={20} aria-hidden="true" />
          Save AI Settings
        </button>
        <button
          type="button"
          className="secondary-button"
          disabled={isTesting}
          onClick={() => {
            void handleTestProxy()
          }}
        >
          {isTesting ? <span className="spinner small" aria-hidden="true" /> : <RefreshCw size={20} />}
          Test Proxy + Weather
        </button>
      </div>
    </form>
  )
}

function normalizedProxyURL(value: string) {
  const baseURL = value.trim().replace(/\/+$/, '')

  if (!baseURL) {
    throw new Error('Enter your Render proxy URL first.')
  }

  return baseURL
}

function proxyURLConfigurationProblem(baseURL: string) {
  const pageHostname = window.location.hostname
  const pageIsLocal = ['localhost', '127.0.0.1', '::1'].includes(pageHostname)
  const proxyIsLocal = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(?::|\/|$)/i.test(baseURL)

  if (!pageIsLocal && proxyIsLocal) {
    return 'This browser is using a localhost proxy URL. Replace it with your Render HTTPS URL, then save.'
  }

  if (window.location.protocol === 'https:' && baseURL.startsWith('http://') && !proxyIsLocal) {
    return 'The proxy URL must use HTTPS when FitCheck is opened from GitHub Pages.'
  }

  return ''
}
