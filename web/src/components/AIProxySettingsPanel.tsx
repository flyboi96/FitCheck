import { type FormEvent, useState } from 'react'
import { Save, ShieldCheck } from 'lucide-react'
import { getAIProxySettings, saveAIProxySettings, type AIProxySettings } from '../lib/settings'

export function AIProxySettingsPanel() {
  const [settings, setSettings] = useState<AIProxySettings>(() => getAIProxySettings())
  const [status, setStatus] = useState<string | null>(null)

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    saveAIProxySettings(settings)
    setStatus('AI proxy settings saved on this device.')
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

      <button type="submit" className="secondary-button">
        <Save size={20} aria-hidden="true" />
        Save AI Settings
      </button>
    </form>
  )
}
