import { useEffect, useState } from 'react'
import { subscribeToClothingItems, type ClothingItem } from '../lib/closet'

export function useClosetItems(userId: string) {
  const [items, setItems] = useState<ClothingItem[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    return subscribeToClothingItems(
      userId,
      (nextItems) => {
        setItems(nextItems)
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
    items,
    isLoading,
    error,
  }
}
