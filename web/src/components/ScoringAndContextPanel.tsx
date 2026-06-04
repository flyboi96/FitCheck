import { useState } from 'react'
import { ListChecks, Plus, Save, SlidersHorizontal, Trash2 } from 'lucide-react'
import { useContextStyles } from '../hooks/useContextStyles'
import {
  createCustomContextDefinition,
  defaultContextStyleSettings,
  saveContextStyles,
  type ContextStyleSettings,
} from '../lib/contextStyles'

export function ScoringGuidePanel() {
  return (
    <section className="profile-form">
      <div className="section-title">
        <ListChecks size={20} aria-hidden="true" />
        <div>
          <p className="eyebrow">Scoring</p>
          <h2>How FitCheck Scores Outfits</h2>
        </div>
      </div>

      <details className="collapsible-card" open>
        <summary>Core outfit roles</summary>
        <p className="helper-text">
          A strong outfit needs a complete role set: top and bottom, or a full-body piece, plus
          shoes. Missing core roles loses points.
        </p>
      </details>

      <details className="collapsible-card">
        <summary>Weather and comfort</summary>
        <p className="helper-text">
          Hot and humid weather rewards lightweight, breathable, short-sleeve, and performance
          pieces. Cold weather rewards layers, wool, pants, jackets, and boots. Your temperature
          comfort setting shifts this.
        </p>
      </details>

      <details className="collapsible-card">
        <summary>Context</summary>
        <p className="helper-text">
          You choose one context for the outfit. The default set starts with Work, Travel, Casual,
          Coastal Casual, Lounge, Going Out, Exploring, Outdoor Recreation, Lifting, and Running,
          but you can rename, remove, or add contexts. FitCheck interprets the selected context
          first, then uses weather separately to adjust fabrics, layers, footwear, and outerwear.
        </p>
      </details>

      <details className="collapsible-card">
        <summary>Fashion rules</summary>
        <p className="helper-text">
          FitCheck penalizes combinations that usually fail: shorts with boots, sweatpants with
          leather boots, belts with bottoms that cannot take a belt, Crocs/clogs/slides for work,
          and polished tops with lounge bottoms.
        </p>
      </details>

      <details className="collapsible-card">
        <summary>Color and personal taste</summary>
        <p className="helper-text">
          Focused palettes, neutrals, and one intentional accent score better. Your profile,
          disliked combinations, rules, feedback, and editable context styles are sent to AI so it
          can apply your personal taste.
        </p>
      </details>

      <details className="collapsible-card">
        <summary>Rotation</summary>
        <p className="helper-text">
          Recently worn washable clothing gets a penalty. Belts and watches are treated as support
          pieces and are not punished the same way as shirts, pants, socks, or underwear.
        </p>
      </details>
    </section>
  )
}

export function ContextStyleEditorPanel({ userId }: { userId: string }) {
  const { error, isLoading, settings } = useContextStyles(userId)
  const [draft, setDraft] = useState<ContextStyleSettings | null>(null)
  const [newContextLabel, setNewContextLabel] = useState('')
  const [isSaving, setIsSaving] = useState(false)
  const [status, setStatus] = useState<string | null>(null)
  const effectiveDraft = draft ?? settings

  async function handleSave() {
    setIsSaving(true)
    setStatus(null)

    try {
      await saveContextStyles(userId, effectiveDraft)
      setDraft(null)
      setStatus('Context styles saved.')
    } catch (saveError) {
      setStatus(saveError instanceof Error ? saveError.message : 'Could not save context styles.')
    } finally {
      setIsSaving(false)
    }
  }

  function updateDefinition(context: string, definition: string) {
    setDraft({
      ...effectiveDraft,
      definitions: effectiveDraft.definitions.map((entry) =>
        entry.context === context ? { ...entry, definition } : entry,
      ),
    })
  }

  function updateLabel(context: string, label: string) {
    setDraft({
      ...effectiveDraft,
      definitions: effectiveDraft.definitions.map((entry) =>
        entry.context === context ? { ...entry, label } : entry,
      ),
    })
  }

  function addContext() {
    const nextDefinition = createCustomContextDefinition(newContextLabel, effectiveDraft.definitions)

    setDraft({
      ...effectiveDraft,
      definitions: [...effectiveDraft.definitions, nextDefinition],
    })
    setNewContextLabel('')
  }

  function removeContext(context: string) {
    if (effectiveDraft.definitions.length <= 1) {
      setStatus('Keep at least one context.')
      return
    }

    setDraft({
      ...effectiveDraft,
      definitions: effectiveDraft.definitions.filter((entry) => entry.context !== context),
    })
  }

  return (
    <section className="profile-form">
      <div className="section-title">
        <SlidersHorizontal size={20} aria-hidden="true" />
        <div>
          <p className="eyebrow">Context</p>
          <h2>Context Styles</h2>
        </div>
      </div>

      <p className="helper-text">
        Add, remove, rename, and define the contexts you want FitCheck to offer. These definitions
        feed Today, Build, Plans, and AI outfit generation.
      </p>

      {isLoading ? <p className="helper-text">Loading context styles.</p> : null}
      {error ? <p className="error-message">{error}</p> : null}

      <div className="context-definition-list">
        {effectiveDraft.definitions.map((definition) => (
          <details className="collapsible-card" key={definition.context}>
            <summary>{definition.label}</summary>
            <label className="form-field">
              <span>Name</span>
              <input
                onChange={(event) => updateLabel(definition.context, event.target.value)}
                type="text"
                value={definition.label}
              />
            </label>
            <label className="form-field">
              <span>Definition</span>
              <textarea
                onChange={(event) => updateDefinition(definition.context, event.target.value)}
                rows={4}
                value={definition.definition}
              />
            </label>
            <button
              type="button"
              className="danger-button full-width"
              onClick={() => removeContext(definition.context)}
            >
              <Trash2 size={18} aria-hidden="true" />
              Remove Context
            </button>
          </details>
        ))}
      </div>

      <div className="photo-import-card">
        <div className="section-title">
          <Plus size={20} aria-hidden="true" />
          <div>
            <p className="eyebrow">Custom</p>
            <h3>Add Context</h3>
          </div>
        </div>
        <label className="form-field">
          <span>Context Name</span>
          <input
            onChange={(event) => setNewContextLabel(event.target.value)}
            placeholder="Brunch, Wedding, Pilot Work, Resort Dinner"
            type="text"
            value={newContextLabel}
          />
        </label>
        <button
          type="button"
          className="secondary-button"
          disabled={!newContextLabel.trim()}
          onClick={addContext}
        >
          <Plus size={20} aria-hidden="true" />
          Add Context
        </button>
      </div>

      <label className="form-field">
        <span>Extra Context Notes</span>
        <textarea
          onChange={(event) => setDraft({ ...effectiveDraft, extraNotes: event.target.value })}
          placeholder="Example: Pilot work and travel are the same for me."
          rows={4}
          value={effectiveDraft.extraNotes}
        />
      </label>

      <div className="generation-actions">
        <button
          type="button"
          className="secondary-button"
          onClick={() => setDraft(defaultContextStyleSettings)}
        >
          Reset Defaults
        </button>
        <button type="button" className="primary-button" disabled={isSaving} onClick={handleSave}>
          {isSaving ? <span className="spinner small" aria-hidden="true" /> : <Save size={20} />}
          Save Contexts
        </button>
      </div>

      {status ? <p className={status.includes('saved') ? 'success-message' : 'error-message'}>{status}</p> : null}
    </section>
  )
}
