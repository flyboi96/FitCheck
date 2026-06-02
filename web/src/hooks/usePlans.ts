import { useEffect, useState } from 'react'
import { subscribeToPlans, type Plan } from '../lib/plans'

export function usePlans(userId: string) {
  const [plans, setPlans] = useState<Plan[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(
    () =>
      subscribeToPlans(
        userId,
        (nextPlans) => {
          setPlans(nextPlans)
          setError(null)
          setIsLoading(false)
        },
        (snapshotError) => {
          setError(snapshotError.message)
          setIsLoading(false)
        },
      ),
    [userId],
  )

  return {
    plans,
    isLoading,
    error,
  }
}
