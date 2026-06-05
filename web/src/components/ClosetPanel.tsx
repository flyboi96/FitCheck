import { type FormEvent, useMemo, useState } from 'react'
import {
  Archive,
  ArrowLeft,
  Camera,
  CheckCircle2,
  Edit3,
  Package,
  Plus,
  Search,
  Shirt,
  Trash2,
  X,
} from 'lucide-react'
import { useClosetItems } from '../hooks/useClosetItems'
import {
  categoryLabel,
  categoryOptionsForWearer,
  clothingCategories,
  clothingStatuses,
  defaultClothingItemDraft,
  deleteAllClothingItems,
  deleteClothingItem,
  saveClothingItem,
  saveClothingItems,
  statusLabel,
  updateClothingItemStatus,
  type ClothingCategory,
  type ClothingItem,
  type ClothingItemDraft,
  type ClothingStatus,
} from '../lib/closet'
import { describeClothingPhoto } from '../lib/photoImport'
import type { WearerProfile } from '../lib/profile'

type StatusFilter = 'all' | ClothingStatus
type CategoryFilter = 'all' | ClothingCategory
type ClosetView = 'list' | 'form' | 'import' | 'bulk'

export function ClosetPanel({
  userId,
  wearerProfile,
}: {
  userId: string
  wearerProfile: WearerProfile
}) {
  const { error, isLoading, items } = useClosetItems(userId)
  const categoryOptions = categoryOptionsForWearer(wearerProfile)
  const [searchTerm, setSearchTerm] = useState('')
  const [categoryFilter, setCategoryFilter] = useState<CategoryFilter>('all')
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('active')
  const [closetView, setClosetView] = useState<ClosetView>('list')
  const [editingItemId, setEditingItemId] = useState<string | null>(null)
  const [draft, setDraft] = useState<ClothingItemDraft>(defaultClothingItemDraft)
  const [isSaving, setIsSaving] = useState(false)
  const [photoFile, setPhotoFile] = useState<File | null>(null)
  const [photoDescription, setPhotoDescription] = useState('')
  const [isImportingPhoto, setIsImportingPhoto] = useState(false)
  const [bulkImportText, setBulkImportText] = useState('')
  const [isBulkImporting, setIsBulkImporting] = useState(false)
  const [isClearingWardrobe, setIsClearingWardrobe] = useState(false)
  const [actionMessage, setActionMessage] = useState<string | null>(null)
  const [actionError, setActionError] = useState<string | null>(null)

  const filteredItems = useMemo(
    () =>
      items.filter((item) => {
        const matchesStatus = statusFilter === 'all' || item.status === statusFilter
        const matchesCategory = categoryFilter === 'all' || item.category === categoryFilter
        const haystack = [
          item.name,
          item.brand,
          categoryLabel(item.category),
          item.color,
          item.material,
          item.pattern,
          item.notes,
          statusLabel(item.status),
        ]
          .join(' ')
          .toLowerCase()
        const matchesSearch = haystack.includes(searchTerm.trim().toLowerCase())

        return matchesStatus && matchesCategory && matchesSearch
      }),
    [categoryFilter, items, searchTerm, statusFilter],
  )

  const groupedItems = useMemo(() => {
    const groups = new Map<ClothingCategory, ClothingItem[]>()

    filteredItems.forEach((item) => {
      const existingItems = groups.get(item.category) ?? []
      groups.set(item.category, [...existingItems, item])
    })

    const displayedCategories = [
      ...categoryOptions,
      ...clothingCategories.filter(
        (category) =>
          groups.has(category.value) &&
          !categoryOptions.some((option) => option.value === category.value),
      ),
    ]

    return displayedCategories
      .map((category) => ({
        category,
        items: groups.get(category.value) ?? [],
      }))
      .filter((group) => group.items.length > 0)
  }, [categoryOptions, filteredItems])

  const activeCount = items.filter((item) => item.status === 'active').length
  const totalQuantity = items.reduce((total, item) => total + item.quantity, 0)
  const unavailableCount = items.filter(
    (item) => item.status === 'laundry' || item.status === 'unavailable',
  ).length

  function openNewItemForm() {
    setDraft({
      ...defaultClothingItemDraft,
      category: categoryOptions[0]?.value ?? 'shirt',
    })
    setEditingItemId(null)
    setClosetView('form')
    setActionMessage(null)
    setActionError(null)
  }

  function openEditForm(item: ClothingItem) {
    setDraft({
      name: item.name,
      brand: item.brand,
      category: item.category,
      quantity: item.quantity,
      color: item.color,
      material: item.material,
      pattern: item.pattern,
      notes: item.notes,
      status: item.status,
    })
    setEditingItemId(item.id)
    setClosetView('form')
    setActionMessage(null)
    setActionError(null)
  }

  function closeForm() {
    setClosetView('list')
    setEditingItemId(null)
    setDraft(defaultClothingItemDraft)
  }

  function openPhotoImport() {
    setClosetView('import')
    setPhotoFile(null)
    setPhotoDescription('')
    setActionMessage(null)
    setActionError(null)
  }

  function openBulkImport() {
    setClosetView('bulk')
    setBulkImportText('')
    setActionMessage(null)
    setActionError(null)
  }

  async function handleSave(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setIsSaving(true)
    setActionMessage(null)
    setActionError(null)

    try {
      await saveClothingItem(userId, draft, editingItemId ?? undefined)
      setActionMessage(editingItemId ? 'Clothing item updated.' : 'Clothing item added.')
      closeForm()
    } catch (saveError) {
      setActionError(saveError instanceof Error ? saveError.message : 'Could not save item.')
    } finally {
      setIsSaving(false)
    }
  }

  async function handleStatusChange(item: ClothingItem, status: ClothingStatus) {
    setActionMessage(null)
    setActionError(null)

    try {
      await updateClothingItemStatus(userId, item.id, status)
      setActionMessage(`${item.name} moved to ${statusLabel(status).toLowerCase()}.`)
    } catch (statusError) {
      setActionError(statusError instanceof Error ? statusError.message : 'Could not update item.')
    }
  }

  async function handleDelete(item: ClothingItem) {
    const confirmed = window.confirm(`Delete "${item.name}" from your closet?`)

    if (!confirmed) {
      return
    }

    setActionMessage(null)
    setActionError(null)

    try {
      await deleteClothingItem(userId, item.id)
      setActionMessage(`${item.name} deleted.`)
    } catch (deleteError) {
      setActionError(deleteError instanceof Error ? deleteError.message : 'Could not delete item.')
    }
  }

  async function handleClearWardrobe() {
    const itemCount = items.length
    const confirmed = window.confirm(
      `Delete all ${itemCount} clothing item${itemCount === 1 ? '' : 's'} from your closet? This cannot be undone.`,
    )

    if (!confirmed) {
      return
    }

    const typedConfirmation = window.prompt('Type DELETE to clear your entire wardrobe.')
    if (typedConfirmation !== 'DELETE') {
      setActionError('Wardrobe clear cancelled. Type DELETE exactly to confirm.')
      return
    }

    setIsClearingWardrobe(true)
    setActionMessage(null)
    setActionError(null)

    try {
      await deleteAllClothingItems(userId)
      setSearchTerm('')
      setCategoryFilter('all')
      setStatusFilter('active')
      setActionMessage('Wardrobe cleared.')
    } catch (clearError) {
      setActionError(clearError instanceof Error ? clearError.message : 'Could not clear wardrobe.')
    } finally {
      setIsClearingWardrobe(false)
    }
  }

  async function handlePhotoImport() {
    if (!photoFile) {
      setActionError('Choose or take a clothing photo first.')
      return
    }

    setIsImportingPhoto(true)
    setActionMessage(null)
    setActionError(null)

    try {
      const importedDraft = await describeClothingPhoto({
        file: photoFile,
        userDescription: photoDescription,
        wearerProfile,
      })
      setDraft(importedDraft)
      setEditingItemId(null)
      setClosetView('form')
      setActionMessage('AI filled the item draft. Review it before saving.')
    } catch (error) {
      setActionError(error instanceof Error ? error.message : 'Photo import failed.')
    } finally {
      setIsImportingPhoto(false)
    }
  }

  async function handleBulkImport() {
    setIsBulkImporting(true)
    setActionMessage(null)
    setActionError(null)

    try {
      const importedDrafts = parseBulkClosetImport(bulkImportText, categoryOptions[0]?.value ?? 'other')
      await saveClothingItems(userId, importedDrafts)
      setActionMessage(`${importedDrafts.length} clothing item${importedDrafts.length === 1 ? '' : 's'} imported.`)
      setBulkImportText('')
      setClosetView('list')
    } catch (error) {
      setActionError(error instanceof Error ? error.message : 'Bulk import failed.')
    } finally {
      setIsBulkImporting(false)
    }
  }

  const statusBlock = (
    <>
      {actionMessage ? <p className="success-message">{actionMessage}</p> : null}
      {actionError || error ? <p className="error-message">{actionError ?? error}</p> : null}
    </>
  )

  if (closetView === 'form') {
    return (
      <div className="closet-panel">
        <ClosetSubpageHeader
          onBack={closeForm}
          subtitle="Closet"
          title={editingItemId ? 'Edit Item' : 'Add Item'}
        />
        {statusBlock}
        <ClothingItemForm
          categoryOptions={categoryOptions}
          draft={draft}
          isEditing={Boolean(editingItemId)}
          isSaving={isSaving}
          onCancel={closeForm}
          onChange={setDraft}
          onSubmit={handleSave}
        />
      </div>
    )
  }

  if (closetView === 'import') {
    return (
      <div className="closet-panel">
        <ClosetSubpageHeader onBack={() => setClosetView('list')} subtitle="Closet" title="Photo Import" />
        {statusBlock}
        <div className="photo-import-card">
          <div className="section-title">
            <Camera size={20} aria-hidden="true" />
            <div>
              <p className="eyebrow">AI import</p>
              <h2>Describe clothing photo</h2>
            </div>
          </div>

          <label className="form-field">
            <span>Photo</span>
            <input
              accept="image/*"
              capture="environment"
              onChange={(event) => setPhotoFile(event.target.files?.[0] ?? null)}
              type="file"
            />
          </label>

          <label className="form-field">
            <span>Optional Description</span>
            <input
              onChange={(event) => setPhotoDescription(event.target.value)}
              placeholder="Brown Thursday Captain boots"
              type="text"
              value={photoDescription}
            />
          </label>

          <button
            type="button"
            className="primary-button"
            disabled={isImportingPhoto}
            onClick={() => {
              void handlePhotoImport()
            }}
          >
            {isImportingPhoto ? <span className="spinner small" aria-hidden="true" /> : <Camera size={20} />}
            Describe Photo
          </button>
        </div>
      </div>
    )
  }

  if (closetView === 'bulk') {
    return (
      <div className="closet-panel">
        <ClosetSubpageHeader onBack={() => setClosetView('list')} subtitle="Closet" title="Bulk Import" />
        {statusBlock}
        <div className="photo-import-card">
          <div className="section-title">
            <Package size={20} aria-hidden="true" />
            <div>
              <p className="eyebrow">First-time setup</p>
              <h2>Paste wardrobe list</h2>
            </div>
          </div>

          <p className="helper-text">
            Add one item per line. Use `name | category | brand | material | notes`. Quantity works at the
            front, like `10x black underwear`.
          </p>

          <label className="form-field">
            <span>Wardrobe Items</span>
            <textarea
              onChange={(event) => setBulkImportText(event.target.value)}
              placeholder={[
                '10x black compression underwear | underwear | Under Armour | synthetic blend',
                'light blue dri-fit short sleeve button-down | shirt | Lululemon | polyester',
                'beige khaki merino wool chino pants | pants | Western Rise | merino wool',
                'brown leather Thursday Captain boots | shoes | Thursday | leather',
              ].join('\n')}
              rows={10}
              value={bulkImportText}
            />
          </label>

          <button
            type="button"
            className="primary-button"
            disabled={isBulkImporting || !bulkImportText.trim()}
            onClick={() => {
              void handleBulkImport()
            }}
          >
            {isBulkImporting ? <span className="spinner small" aria-hidden="true" /> : <Package size={20} />}
            Import Items
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="closet-panel">
      <div className="summary-grid" aria-label="Closet summary">
        <SummaryCard label="Active" value={activeCount.toString()} />
        <SummaryCard label="Total Qty" value={totalQuantity.toString()} />
        <SummaryCard label="Unavailable" value={unavailableCount.toString()} />
      </div>

      <div className="closet-toolbar">
        <label className="search-field">
          <Search size={18} aria-hidden="true" />
          <input
            onChange={(event) => setSearchTerm(event.target.value)}
            placeholder="Search closet"
            type="search"
            value={searchTerm}
          />
        </label>
        <div className="split-action-row">
          <button type="button" className="primary-button" onClick={openNewItemForm}>
            <Plus size={20} aria-hidden="true" />
            Add Item
          </button>
          <button type="button" className="secondary-button" onClick={openBulkImport}>
            <Package size={20} aria-hidden="true" />
            Bulk Import
          </button>
          <button type="button" className="secondary-button" onClick={openPhotoImport}>
            <Camera size={20} aria-hidden="true" />
            Photo Import
          </button>
          <button
            type="button"
            className="danger-button"
            disabled={items.length === 0 || isClearingWardrobe}
            onClick={() => {
              void handleClearWardrobe()
            }}
          >
            {isClearingWardrobe ? <span className="spinner small" aria-hidden="true" /> : <Trash2 size={18} />}
            Clear Wardrobe
          </button>
        </div>
      </div>

      <div className="filter-row">
        <label className="form-field compact">
          <span>Category</span>
          <select
            onChange={(event) => setCategoryFilter(event.target.value as CategoryFilter)}
            value={categoryFilter}
          >
            <option value="all">All categories</option>
            {categoryOptions.map((category) => (
              <option key={category.value} value={category.value}>
                {category.label}
              </option>
            ))}
          </select>
        </label>

        <label className="form-field compact">
          <span>Status</span>
          <select
            onChange={(event) => setStatusFilter(event.target.value as StatusFilter)}
            value={statusFilter}
          >
            <option value="all">All statuses</option>
            {clothingStatuses.map((status) => (
              <option key={status.value} value={status.value}>
                {status.label}
              </option>
            ))}
          </select>
        </label>
      </div>

      {statusBlock}

      {isLoading ? (
        <div className="placeholder-panel">
          <span className="spinner small" aria-hidden="true" />
          <div>
            <h3>Loading closet</h3>
            <p>Reading your clothing items from Firestore.</p>
          </div>
        </div>
      ) : null}

      {!isLoading && items.length > 0 && filteredItems.length === 0 ? (
        <div className="empty-state">
          <Search size={24} aria-hidden="true" />
          <h3>No matching items</h3>
          <p>Clear the search or switch filters to see more of your closet.</p>
        </div>
      ) : null}

      {!isLoading && items.length === 0 ? (
        <div className="empty-state">
          <Shirt size={24} aria-hidden="true" />
          <h3>Start your closet</h3>
          <p>Add the clothes you actually own. This becomes the source for outfit planning.</p>
        </div>
      ) : null}

      <div className="closet-list" aria-label="Clothing items">
        {groupedItems.map((group) => (
          <section className="category-section" key={group.category.value}>
            <div className="category-heading">
              <h3>{group.category.label}</h3>
              <span>{group.items.length}</span>
            </div>
            <div className="item-list">
              {group.items.map((item) => (
                <ClothingItemCard
                  item={item}
                  key={item.id}
                  onArchive={() =>
                    handleStatusChange(item, item.status === 'archived' ? 'active' : 'archived')
                  }
                  onDelete={() => {
                    void handleDelete(item)
                  }}
                  onEdit={() => openEditForm(item)}
                />
              ))}
            </div>
          </section>
        ))}
      </div>
    </div>
  )
}

function ClosetSubpageHeader({
  onBack,
  subtitle,
  title,
}: {
  onBack: () => void
  subtitle: string
  title: string
}) {
  return (
    <div className="subpage-header">
      <button type="button" className="icon-button" onClick={onBack} aria-label="Back">
        <ArrowLeft size={22} />
      </button>
      <div>
        <p className="eyebrow">{subtitle}</p>
        <h2>{title}</h2>
      </div>
    </div>
  )
}

function SummaryCard({ label, value }: { label: string; value: string }) {
  return (
    <article className="summary-card">
      <strong>{value}</strong>
      <span>{label}</span>
    </article>
  )
}

function parseBulkClosetImport(input: string, fallbackCategory: ClothingCategory): ClothingItemDraft[] {
  const drafts = input
    .split(/\r?\n/)
    .map((line) => parseBulkImportLine(line, fallbackCategory))
    .filter((draft): draft is ClothingItemDraft => Boolean(draft))

  if (drafts.length === 0) {
    throw new Error('Paste at least one item line first.')
  }

  return drafts
}

function parseBulkImportLine(line: string, fallbackCategory: ClothingCategory): ClothingItemDraft | null {
  const trimmedLine = line.trim()

  if (!trimmedLine) {
    return null
  }

  const segments = trimmedLine.split('|').map((segment) => segment.trim())
  const parsedName = parseQuantityPrefix(segments[0])
  const categoryFromSegment = categoryFromText(segments[1])
  const category = categoryFromSegment ?? inferCategoryFromName(parsedName.name) ?? fallbackCategory
  const brand = categoryFromSegment ? segments[2] ?? '' : segments[1] ?? ''
  const material = categoryFromSegment ? segments[3] ?? '' : segments[2] ?? ''
  const notes = categoryFromSegment ? segments.slice(4).join(' | ') : segments.slice(3).join(' | ')

  return {
    ...defaultClothingItemDraft,
    name: parsedName.name,
    brand,
    category,
    quantity: parsedName.quantity,
    material,
    notes,
  }
}

function parseQuantityPrefix(value: string) {
  const trimmedValue = value.trim()
  const quantityMatch = trimmedValue.match(/^(\d+)\s*(?:x|×)\s+(.+)$/i)

  if (!quantityMatch) {
    return {
      name: trimmedValue,
      quantity: 1,
    }
  }

  return {
    name: quantityMatch[2].trim(),
    quantity: Math.max(1, Number.parseInt(quantityMatch[1], 10) || 1),
  }
}

function categoryFromText(value?: string): ClothingCategory | null {
  const normalizedValue = value?.trim().toLowerCase()

  if (!normalizedValue) {
    return null
  }

  return (
    clothingCategories.find(
      (category) =>
        category.value.toLowerCase() === normalizedValue ||
        category.label.toLowerCase() === normalizedValue,
    )?.value ?? null
  )
}

function inferCategoryFromName(name: string): ClothingCategory | null {
  const text = name.toLowerCase()

  if (/underwear|boxer|brief|compression short/.test(text)) return 'underwear'
  if (/sock/.test(text)) return 'socks'
  if (/belt/.test(text)) return 'belt'
  if (/watch/.test(text)) return 'watch'
  if (/ring|necklace|bracelet|earring|jewelry/.test(text)) return 'jewelry'
  if (/purse/.test(text)) return 'purse'
  if (/bag|backpack|duffel|tote/.test(text)) return 'bag'
  if (/heel/.test(text)) return 'heels'
  if (/flat/.test(text)) return 'flats'
  if (/shoe|sneaker|boot|loafer|sandal|flip[- ]?flop|clog|crocs|trainer|runner/.test(text)) {
    return 'shoes'
  }
  if (/jacket|coat|shell|rain shell|windbreaker|parka/.test(text)) return 'jacket'
  if (/sweater|hoodie|sweatshirt|fleece/.test(text)) return 'sweater'
  if (/dress/.test(text)) return 'dress'
  if (/skirt/.test(text)) return 'skirt'
  if (/blouse/.test(text)) return 'blouse'
  if (/running|lifting|workout|gym|training/.test(text)) return 'activewear'
  if (/shorts?/.test(text)) return 'shorts'
  if (/pants?|chino|jeans?|trousers?|joggers?|sweatpants?/.test(text)) return 'pants'
  if (/shirt|tee|t-shirt|button[- ]?down|polo|henley|tank|top/.test(text)) return 'shirt'

  return null
}

function ClothingItemForm({
  categoryOptions,
  draft,
  isEditing,
  isSaving,
  onCancel,
  onChange,
  onSubmit,
}: {
  categoryOptions: ReturnType<typeof categoryOptionsForWearer>
  draft: ClothingItemDraft
  isEditing: boolean
  isSaving: boolean
  onCancel?: () => void
  onChange: (draft: ClothingItemDraft) => void
  onSubmit: (event: FormEvent<HTMLFormElement>) => void
}) {
  return (
    <form className="closet-form" onSubmit={onSubmit}>
      <div className="form-title-row">
        <div>
          <p className="eyebrow">{isEditing ? 'Edit item' : 'New item'}</p>
          <h3>{isEditing ? 'Update clothing item' : 'Add clothing item'}</h3>
        </div>
        {onCancel ? (
          <button type="button" className="icon-button" onClick={onCancel} aria-label="Close form">
            <X size={20} />
          </button>
        ) : null}
      </div>

      <label className="form-field">
        <span>Name</span>
        <input
          onChange={(event) => onChange({ ...draft, name: event.target.value })}
          placeholder="Blue merino wool button-down"
          required
          type="text"
          value={draft.name}
        />
      </label>

      <div className="two-column-fields">
        <label className="form-field">
          <span>Category</span>
          <select
            onChange={(event) =>
              onChange({ ...draft, category: event.target.value as ClothingCategory })
            }
            value={draft.category}
          >
            {categoryOptions.map((category) => (
              <option key={category.value} value={category.value}>
                {category.label}
              </option>
            ))}
          </select>
        </label>

        <label className="form-field">
          <span>Quantity</span>
          <input
            min={1}
            onChange={(event) =>
              onChange({ ...draft, quantity: Number.parseInt(event.target.value, 10) || 1 })
            }
            type="number"
            value={draft.quantity}
          />
        </label>
      </div>

      <div className="two-column-fields">
        <label className="form-field">
          <span>Brand</span>
          <input
            onChange={(event) => onChange({ ...draft, brand: event.target.value })}
            placeholder="Lululemon"
            type="text"
            value={draft.brand}
          />
        </label>

        <label className="form-field">
          <span>Status</span>
          <select
            onChange={(event) =>
              onChange({ ...draft, status: event.target.value as ClothingStatus })
            }
            value={draft.status}
          >
            {clothingStatuses.map((status) => (
              <option key={status.value} value={status.value}>
                {status.label}
              </option>
            ))}
          </select>
        </label>
      </div>

      <div className="two-column-fields">
        <label className="form-field">
          <span>Color</span>
          <input
            onChange={(event) => onChange({ ...draft, color: event.target.value })}
            placeholder="Light blue"
            type="text"
            value={draft.color}
          />
        </label>

        <label className="form-field">
          <span>Pattern</span>
          <input
            onChange={(event) => onChange({ ...draft, pattern: event.target.value })}
            placeholder="Solid"
            type="text"
            value={draft.pattern}
          />
        </label>
      </div>

      <label className="form-field">
        <span>Material</span>
        <input
          onChange={(event) => onChange({ ...draft, material: event.target.value })}
          placeholder="Merino wool, cotton, leather, synthetic blend"
          type="text"
          value={draft.material}
        />
      </label>

      <label className="form-field">
        <span>Notes</span>
        <textarea
          onChange={(event) => onChange({ ...draft, notes: event.target.value })}
          placeholder="Fit, material, weather use, personal rules, or laundry notes."
          rows={4}
          value={draft.notes}
        />
      </label>

      <button type="submit" className="primary-button" disabled={isSaving}>
        {isSaving ? <span className="spinner small" aria-hidden="true" /> : <CheckCircle2 size={20} />}
        {isEditing ? 'Save Changes' : 'Add to Closet'}
      </button>
    </form>
  )
}

function ClothingItemCard({
  item,
  onArchive,
  onDelete,
  onEdit,
}: {
  item: ClothingItem
  onArchive: () => void
  onDelete: () => void
  onEdit: () => void
}) {
  const detailParts = [
    categoryLabel(item.category),
    item.brand || null,
    item.color || null,
    item.material || null,
    item.pattern || null,
  ].filter(Boolean)

  return (
    <article className="closet-item-card">
      <div className="item-icon" aria-hidden="true">
        <Package size={20} />
      </div>
      <div className="item-content">
        <div className="item-title-row">
          <div>
            <h3>{item.name}</h3>
            <p>{detailParts.join(' - ')}</p>
          </div>
          <span className="quantity-chip">Qty {item.quantity}</span>
        </div>

        {item.notes ? <p className="item-notes">{item.notes}</p> : null}

        <div className="item-footer">
          <span className={`status-chip ${item.status}`}>{statusLabel(item.status)}</span>
          <span>Worn {item.wearCount}x</span>
        </div>

        <div className="item-actions">
          <button type="button" className="ghost-button" onClick={onEdit}>
            <Edit3 size={18} aria-hidden="true" />
            Edit
          </button>
          <button type="button" className="ghost-button" onClick={onArchive}>
            <Archive size={18} aria-hidden="true" />
            {item.status === 'archived' ? 'Restore' : 'Archive'}
          </button>
          <button type="button" className="danger-button" onClick={onDelete}>
            <Trash2 size={18} aria-hidden="true" />
            Delete
          </button>
        </div>
      </div>
    </article>
  )
}
