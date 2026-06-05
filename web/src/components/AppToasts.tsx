import { useEffect, useState } from 'react'
import { toastEventName, type AppToast } from '../lib/appToasts'

export function AppToastHost() {
  const [toasts, setToasts] = useState<AppToast[]>([])

  useEffect(() => {
    function handleToast(event: Event) {
      const toast = (event as CustomEvent<AppToast>).detail

      if (!toast?.message) {
        return
      }

      setToasts((currentToasts) => [...currentToasts.slice(-2), toast])
      window.setTimeout(() => {
        setToasts((currentToasts) => currentToasts.filter((currentToast) => currentToast.id !== toast.id))
      }, 3200)
    }

    window.addEventListener(toastEventName, handleToast)
    return () => window.removeEventListener(toastEventName, handleToast)
  }, [])

  if (toasts.length === 0) {
    return null
  }

  return (
    <div className="toast-stack" aria-live="polite" aria-label="App status">
      {toasts.map((toast) => (
        <div className={`app-toast ${toast.tone}`} key={toast.id}>
          {toast.message}
        </div>
      ))}
    </div>
  )
}
