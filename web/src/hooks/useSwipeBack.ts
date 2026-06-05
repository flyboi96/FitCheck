import { useRef, type TouchEventHandler } from 'react'

type SwipePoint = {
  time: number
  x: number
  y: number
}

const edgeWidth = 44
const minHorizontalTravel = 76
const maxVerticalTravel = 56
const maxSwipeMs = 800

export function useSwipeBack(onBack: () => void, enabled: boolean) {
  const startPoint = useRef<SwipePoint | null>(null)

  const onTouchStart: TouchEventHandler<HTMLElement> = (event) => {
    if (!enabled || event.touches.length !== 1) {
      startPoint.current = null
      return
    }

    const touch = event.touches[0]
    startPoint.current = {
      time: Date.now(),
      x: touch.clientX,
      y: touch.clientY,
    }
  }

  const onTouchEnd: TouchEventHandler<HTMLElement> = (event) => {
    const start = startPoint.current
    startPoint.current = null

    if (!enabled || !start || event.changedTouches.length !== 1) {
      return
    }

    const touch = event.changedTouches[0]
    const deltaX = touch.clientX - start.x
    const deltaY = touch.clientY - start.y
    const elapsedMs = Date.now() - start.time
    const screenWidth = window.innerWidth
    const startedAtLeftEdge = start.x <= edgeWidth
    const startedAtRightEdge = start.x >= screenWidth - edgeWidth
    const isFastEnough = elapsedMs <= maxSwipeMs
    const isHorizontal = Math.abs(deltaY) <= maxVerticalTravel
    const isLeftEdgeBack = startedAtLeftEdge && deltaX >= minHorizontalTravel
    const isRightEdgeBack = startedAtRightEdge && deltaX <= -minHorizontalTravel

    if (isFastEnough && isHorizontal && (isLeftEdgeBack || isRightEdgeBack)) {
      event.stopPropagation()
      onBack()
    }
  }

  return {
    onTouchEnd,
    onTouchStart,
  }
}
