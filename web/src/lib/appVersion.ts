export const appVersion = import.meta.env.VITE_FITCHECK_APP_VERSION || '1.4.0'

const rawBuildId = import.meta.env.VITE_FITCHECK_BUILD_ID || 'local'
const buildId = rawBuildId === 'local' ? 'local' : rawBuildId.slice(0, 7)

export const appVersionLabel = `v${appVersion} ${buildId}`
