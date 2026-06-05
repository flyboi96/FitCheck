export type ToastTone = 'error' | 'success' | 'info'

export type AppToast = {
  id: string
  message: string
  tone: ToastTone
}

export const toastEventName = 'fitcheck:toast'

export function showAppToast(message: string, tone: ToastTone = 'info') {
  window.dispatchEvent(
    new CustomEvent<AppToast>(toastEventName, {
      detail: {
        id: crypto.randomUUID(),
        message,
        tone,
      },
    }),
  )
}
