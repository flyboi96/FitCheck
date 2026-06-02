import { useEffect, useState } from 'react'
import {
  defaultContextStyleSettings,
  subscribeToContextStyles,
  type ContextStyleSettings,
} from '../lib/contextStyles'

export function useContextStyles(userId: string) {
  const [settings, setSettings] = useState<ContextStyleSettings>(defaultContextStyleSettings)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    return subscribeToContextStyles(
      userId,
      (nextSettings) => {
        setSettings(nextSettings)
        setError(null)
        setIsLoading(false)
      },
      (snapshotError) => {
        setError(snapshotError.message)
        setIsLoading(false)
      },
    )
  }, [userId])

  return {
    settings,
    isLoading,
    error,
  }
}
