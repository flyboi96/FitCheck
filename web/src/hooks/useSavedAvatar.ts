import { useEffect, useState } from 'react'
import { subscribeToSavedAvatar, type SavedAvatar } from '../lib/avatar'

export function useSavedAvatar(userId: string) {
  const [avatar, setAvatar] = useState<SavedAvatar | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    return subscribeToSavedAvatar(
      userId,
      (nextAvatar) => {
        setAvatar(nextAvatar)
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
    avatar,
    isLoading,
    error,
  }
}
