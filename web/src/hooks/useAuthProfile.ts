import { onAuthStateChanged, type User } from 'firebase/auth'
import { useCallback, useEffect, useState } from 'react'
import { auth } from '../lib/firebase'
import { ensureUserProfile, type UserProfile } from '../lib/profile'

export function useAuthProfile() {
  const [user, setUser] = useState<User | null>(null)
  const [profile, setProfile] = useState<UserProfile | null>(null)
  const [isLoading, setIsLoading] = useState(() => Boolean(auth))
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!auth) {
      return undefined
    }

    return onAuthStateChanged(auth, async (nextUser) => {
      setUser(nextUser)
      setError(null)

      if (!nextUser) {
        setProfile(null)
        setIsLoading(false)
        return
      }

      try {
        setIsLoading(true)
        setProfile(await ensureUserProfile(nextUser))
      } catch (profileError) {
        setError(profileError instanceof Error ? profileError.message : 'Could not load profile.')
      } finally {
        setIsLoading(false)
      }
    })
  }, [])

  const refreshProfile = useCallback(async () => {
    if (!user) {
      return
    }

    setProfile(await ensureUserProfile(user))
  }, [user])

  return {
    user,
    profile,
    isLoading,
    error,
    refreshProfile,
  }
}
