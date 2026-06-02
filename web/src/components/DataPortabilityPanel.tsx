import { useState } from 'react'
import { Download, FileUp } from 'lucide-react'
import {
  downloadBackup,
  exportFitCheckBackup,
  importFitCheckBackup,
} from '../lib/backup'

export function DataPortabilityPanel({ userId }: { userId: string }) {
  const [isWorking, setIsWorking] = useState(false)
  const [status, setStatus] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [importFile, setImportFile] = useState<File | null>(null)

  async function handleExport() {
    setIsWorking(true)
    setStatus(null)
    setError(null)

    try {
      const json = await exportFitCheckBackup(userId)
      downloadBackup(json)
      setStatus('Backup exported as JSON.')
    } catch (exportError) {
      setError(exportError instanceof Error ? exportError.message : 'Could not export backup.')
    } finally {
      setIsWorking(false)
    }
  }

  async function handleImport() {
    if (!importFile) {
      setError('Choose a FitCheck backup JSON file first.')
      return
    }

    const confirmed = window.confirm(
      'Importing replaces closet, plans, history, feedback, avatar, and context settings for this account. Continue?',
    )

    if (!confirmed) {
      return
    }

    setIsWorking(true)
    setStatus(null)
    setError(null)

    try {
      await importFitCheckBackup(userId, importFile)
      setImportFile(null)
      setStatus('Backup imported. Firestore will sync the restored data.')
    } catch (importError) {
      setError(importError instanceof Error ? importError.message : 'Could not import backup.')
    } finally {
      setIsWorking(false)
    }
  }

  return (
    <section className="profile-form">
      <div className="section-title">
        <Download size={20} aria-hidden="true" />
        <div>
          <p className="eyebrow">Data</p>
          <h2>Backup / Export / Import</h2>
        </div>
      </div>

      <p className="helper-text">
        Exports profile, closet, plans, generated itinerary, packing list, history, feedback,
        avatar metadata, and context styles as one JSON file.
      </p>

      <button type="button" className="secondary-button" disabled={isWorking} onClick={handleExport}>
        {isWorking ? <span className="spinner small" aria-hidden="true" /> : <Download size={20} />}
        Export JSON Backup
      </button>

      <label className="form-field">
        <span>Import Backup JSON</span>
        <input
          accept="application/json,.json"
          onChange={(event) => setImportFile(event.target.files?.[0] ?? null)}
          type="file"
        />
      </label>

      <button
        type="button"
        className="danger-button full-width"
        disabled={isWorking || !importFile}
        onClick={() => {
          void handleImport()
        }}
      >
        <FileUp size={18} aria-hidden="true" />
        Import and Replace Data
      </button>

      {status ? <p className="success-message">{status}</p> : null}
      {error ? <p className="error-message">{error}</p> : null}
    </section>
  )
}
