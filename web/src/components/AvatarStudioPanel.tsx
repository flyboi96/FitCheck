import { useState } from 'react'
import { Camera, Download, Image as ImageIcon, Save, Sparkles, Trash2 } from 'lucide-react'
import { useSavedAvatar } from '../hooks/useSavedAvatar'
import {
  deleteSavedAvatar,
  generateBaseAvatar,
  saveGeneratedAvatar,
  saveReferenceAvatar,
  type AvatarPreview,
} from '../lib/avatar'
import type { UserProfile } from '../lib/profile'

export function AvatarStudioPanel({
  profile,
  userId,
}: {
  profile: UserProfile | null
  userId: string
}) {
  const { avatar, error: avatarError, isLoading } = useSavedAvatar(userId)
  const [file, setFile] = useState<File | null>(null)
  const [notes, setNotes] = useState('')
  const [generatedAvatar, setGeneratedAvatar] = useState<AvatarPreview | null>(null)
  const [isWorking, setIsWorking] = useState(false)
  const [status, setStatus] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function handleGenerateBaseAvatar() {
    if (!file) {
      setError('Choose a full-body reference photo first.')
      return
    }

    setIsWorking(true)
    setStatus(null)
    setError(null)

    try {
      const nextAvatar = await generateBaseAvatar({ file, notes, profile })
      setGeneratedAvatar(nextAvatar)
      setStatus('Base avatar generated. Save it to reuse for outfit previews.')
    } catch (generateError) {
      setError(generateError instanceof Error ? generateError.message : 'Could not generate avatar.')
    } finally {
      setIsWorking(false)
    }
  }

  async function handleSaveGeneratedAvatar() {
    if (!generatedAvatar) {
      return
    }

    setIsWorking(true)
    setStatus(null)
    setError(null)

    try {
      await saveGeneratedAvatar({ avatar: generatedAvatar, notes, userId })
      setStatus('Saved avatar for future previews.')
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Could not save avatar.')
    } finally {
      setIsWorking(false)
    }
  }

  async function handleSaveReferencePhoto() {
    if (!file) {
      setError('Choose a full-body reference photo first.')
      return
    }

    setIsWorking(true)
    setStatus(null)
    setError(null)

    try {
      await saveReferenceAvatar({ file, notes, userId })
      setStatus('Saved reference photo for future previews.')
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Could not save reference photo.')
    } finally {
      setIsWorking(false)
    }
  }

  async function handleDeleteAvatar() {
    if (!window.confirm('Delete the saved avatar?')) {
      return
    }

    setIsWorking(true)
    setStatus(null)
    setError(null)

    try {
      await deleteSavedAvatar(userId)
      setGeneratedAvatar(null)
      setStatus('Saved avatar deleted.')
    } catch (deleteError) {
      setError(deleteError instanceof Error ? deleteError.message : 'Could not delete avatar.')
    } finally {
      setIsWorking(false)
    }
  }

  return (
    <section className="profile-form">
      <div className="section-title">
        <ImageIcon size={20} aria-hidden="true" />
        <div>
          <p className="eyebrow">Avatar</p>
          <h2>Avatar Studio</h2>
        </div>
      </div>

      <p className="helper-text">
        Save one full-body avatar so outfit previews do not need a new photo every time.
      </p>

      {isLoading ? <p className="helper-text">Loading saved avatar.</p> : null}
      {avatarError ? <p className="error-message">{avatarError}</p> : null}
      {status ? <p className="success-message">{status}</p> : null}
      {error ? <p className="error-message">{error}</p> : null}

      {avatar ? (
        <div className="avatar-preview-result">
          <img alt="Saved FitCheck avatar" src={avatar.imageURL} />
          {avatar.notes ? <p className="helper-text">{avatar.notes}</p> : null}
          <div className="two-column-fields">
            <a className="secondary-button" download="fitcheck-saved-avatar.png" href={avatar.imageURL}>
              <Download size={20} aria-hidden="true" />
              Save Image
            </a>
            <button
              type="button"
              className="danger-button"
              disabled={isWorking}
              onClick={() => {
                void handleDeleteAvatar()
              }}
            >
              <Trash2 size={18} aria-hidden="true" />
              Delete Avatar
            </button>
          </div>
        </div>
      ) : (
        <div className="empty-state">
          <Camera size={24} aria-hidden="true" />
          <h3>No saved avatar</h3>
          <p>Choose from Photos or take a clear full-body photo with head, hair, and shoes visible.</p>
        </div>
      )}

      <label className="form-field">
        <span>Reference Photo</span>
        <input
          accept="image/*"
          onChange={(event) => setFile(event.target.files?.[0] ?? null)}
          type="file"
        />
      </label>
      {file ? <p className="helper-text">Selected: {file.name}</p> : null}

      <label className="form-field">
        <span>Avatar Notes</span>
        <textarea
          onChange={(event) => setNotes(event.target.value)}
          placeholder="Example: full-body, natural posture, keep hair visible, neutral expression."
          rows={3}
          value={notes}
        />
      </label>

      <div className="generation-actions">
        <button
          type="button"
          className="primary-button"
          disabled={isWorking}
          onClick={() => {
            void handleGenerateBaseAvatar()
          }}
        >
          {isWorking ? <span className="spinner small" aria-hidden="true" /> : <Sparkles size={20} />}
          Generate Base
        </button>
        <button
          type="button"
          className="secondary-button"
          disabled={isWorking}
          onClick={() => {
            void handleSaveReferencePhoto()
          }}
        >
          <Save size={20} aria-hidden="true" />
          Save Reference
        </button>
      </div>

      {generatedAvatar ? (
        <div className="avatar-preview-result">
          <img alt="Generated base avatar" src={generatedAvatar.imageURL} />
          <p className="helper-text">{generatedAvatar.promptSummary}</p>
          <button
            type="button"
            className="secondary-button"
            disabled={isWorking}
            onClick={() => {
              void handleSaveGeneratedAvatar()
            }}
          >
            <Save size={20} aria-hidden="true" />
            Save Generated Avatar
          </button>
        </div>
      ) : null}
    </section>
  )
}
