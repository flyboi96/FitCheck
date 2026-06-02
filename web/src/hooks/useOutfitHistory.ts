import { useEffect, useState } from 'react'
import {
  subscribeToOutfitHistory,
  subscribeToWearLogs,
  type LoggedOutfit,
  type WearLog,
} from '../lib/history'

export function useOutfitHistory(userId: string) {
  const [outfits, setOutfits] = useState<LoggedOutfit[]>([])
  const [wearLogs, setWearLogs] = useState<WearLog[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let pendingSnapshots = 2

    const markLoaded = () => {
      pendingSnapshots -= 1
      if (pendingSnapshots <= 0) {
        setIsLoading(false)
      }
    }

    const unsubscribeOutfits = subscribeToOutfitHistory(
      userId,
      (nextOutfits) => {
        setOutfits(nextOutfits)
        setError(null)
        markLoaded()
      },
      (snapshotError) => {
        setError(snapshotError.message)
        setIsLoading(false)
      },
    )
    const unsubscribeWearLogs = subscribeToWearLogs(
      userId,
      (nextWearLogs) => {
        setWearLogs(nextWearLogs)
        setError(null)
        markLoaded()
      },
      (snapshotError) => {
        setError(snapshotError.message)
        setIsLoading(false)
      },
    )

    return () => {
      unsubscribeOutfits()
      unsubscribeWearLogs()
    }
  }, [userId])

  return {
    outfits,
    wearLogs,
    isLoading,
    error,
  }
}
