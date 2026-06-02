export type AIProxySettings = {
  proxyUrl: string
  proxyToken: string
}

const proxyUrlKey = 'fitcheck.proxyUrl'
const proxyTokenKey = 'fitcheck.proxyToken'

export function getAIProxySettings(): AIProxySettings {
  return {
    proxyUrl: localStorage.getItem(proxyUrlKey) ?? import.meta.env.VITE_FITCHECK_PROXY_URL ?? '',
    proxyToken:
      localStorage.getItem(proxyTokenKey) ?? import.meta.env.VITE_FITCHECK_PROXY_TOKEN ?? '',
  }
}

export function saveAIProxySettings(settings: AIProxySettings) {
  localStorage.setItem(proxyUrlKey, settings.proxyUrl.trim())
  localStorage.setItem(proxyTokenKey, settings.proxyToken.trim())
}
