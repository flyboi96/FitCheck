import { useMemo, useState } from 'react'
import { CalendarDays, RotateCcw, Trash2 } from 'lucide-react'
import { useClosetItems } from '../hooks/useClosetItems'
import { useOutfitHistory } from '../hooks/useOutfitHistory'
import {
  clearOutfitHistory,
  deleteLoggedOutfit,
  formatShortDate,
  wearCountLabel,
  type WearLog,
} from '../lib/history'

export function HistoryPanel({ userId }: { userId: string }) {
  const { error, isLoading, outfits, wearLogs } = useOutfitHistory(userId)
  const { items } = useClosetItems(userId)
  const [status, setStatus] = useState<string | null>(null)
  const [actionError, setActionError] = useState<string | null>(null)

  const logsByItem = useMemo(() => {
    const groups = new Map<string, WearLog[]>()

    wearLogs.forEach((log) => {
      groups.set(log.itemID, [...(groups.get(log.itemID) ?? []), log])
    })

    return [...groups.entries()]
      .map(([itemID, logs]) => ({
        itemID,
        itemName: logs[0]?.itemName ?? 'Unknown item',
        logs,
      }))
      .sort((first, second) => first.itemName.localeCompare(second.itemName))
  }, [wearLogs])

  async function handleDelete(outfitId: string) {
    const outfit = outfits.find((entry) => entry.id === outfitId)
    if (!outfit) {
      return
    }

    setStatus(null)
    setActionError(null)

    try {
      await deleteLoggedOutfit(userId, outfit)
      setStatus('Outfit history item deleted.')
    } catch (deleteError) {
      setActionError(deleteError instanceof Error ? deleteError.message : 'Could not delete outfit.')
    }
  }

  async function handleClear() {
    if (!window.confirm('Clear all logged outfits and reset wear counts?')) {
      return
    }

    setStatus(null)
    setActionError(null)

    try {
      await clearOutfitHistory(userId)
      setStatus('Outfit history cleared.')
    } catch (clearError) {
      setActionError(clearError instanceof Error ? clearError.message : 'Could not clear history.')
    }
  }

  return (
    <section className="profile-form">
      <div className="section-title">
        <CalendarDays size={20} aria-hidden="true" />
        <div>
          <p className="eyebrow">Records</p>
          <h2>Outfit History</h2>
        </div>
      </div>

      {isLoading ? (
        <p className="helper-text">
          <span className="spinner small" aria-hidden="true" /> Loading outfit history.
        </p>
      ) : null}
      {error ? <p className="error-message">{error}</p> : null}
      {actionError ? <p className="error-message">{actionError}</p> : null}
      {status ? <p className="success-message">{status}</p> : null}

      <div className="history-summary-grid">
        <div className="summary-card">
          <strong>{outfits.length}</strong>
          <span>Logged outfits</span>
        </div>
        <div className="summary-card">
          <strong>{wearLogs.length}</strong>
          <span>Item wears</span>
        </div>
        <div className="summary-card">
          <strong>{items.filter((item) => item.wearCount > 0).length}</strong>
          <span>Items worn</span>
        </div>
      </div>

      {outfits.length > 0 ? (
        <button type="button" className="danger-button full-width" onClick={handleClear}>
          <RotateCcw size={18} aria-hidden="true" />
          Clear History
        </button>
      ) : null}

      <details className="collapsible-card" open>
        <summary>Logged Outfits</summary>
        {outfits.length === 0 ? (
          <p className="helper-text">No outfits logged yet.</p>
        ) : (
          <div className="history-list">
            {outfits.map((outfit) => (
              <article className="history-card" key={outfit.id}>
                <div className="history-card-header">
                  <div>
                    <h3>{outfit.name}</h3>
                    <p className="helper-text">
                      {formatShortDate(outfit.wornAt)} - {outfit.contextLabel}
                    </p>
                  </div>
                  <button
                    type="button"
                    className="danger-button icon-sized"
                    aria-label={`Delete ${outfit.name}`}
                    onClick={() => {
                      void handleDelete(outfit.id)
                    }}
                  >
                    <Trash2 size={18} aria-hidden="true" />
                  </button>
                </div>
                <p className="helper-text">{outfit.weatherSummary}</p>
                <ul>
                  {outfit.itemNames.map((itemName) => (
                    <li key={itemName}>{itemName}</li>
                  ))}
                </ul>
                {outfit.note ? <p className="helper-text">Note: {outfit.note}</p> : null}
              </article>
            ))}
          </div>
        )}
      </details>

      <details className="collapsible-card">
        <summary>Item Rotation</summary>
        <div className="history-list">
          {items
            .slice()
            .sort((first, second) => second.wearCount - first.wearCount)
            .map((item) => (
              <div className="rotation-row" key={item.id}>
                <strong>{item.name}</strong>
                <span>{wearCountLabel(item)}</span>
              </div>
            ))}
        </div>
      </details>

      <details className="collapsible-card">
        <summary>Wear Logs by Item</summary>
        {logsByItem.length === 0 ? (
          <p className="helper-text">No item wear logs yet.</p>
        ) : (
          <div className="history-list">
            {logsByItem.map((group) => (
              <details className="nested-details" key={group.itemID}>
                <summary>
                  {group.itemName} ({group.logs.length})
                </summary>
                <ul>
                  {group.logs.map((log) => (
                    <li key={log.id}>
                      {formatShortDate(log.wornAt)} - {log.outfitName}
                    </li>
                  ))}
                </ul>
              </details>
            ))}
          </div>
        )}
      </details>
    </section>
  )
}
