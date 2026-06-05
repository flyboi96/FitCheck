import { useId, useMemo, useState } from 'react'
import { Search } from 'lucide-react'
import {
  categoryLabel,
  clothingCategories,
  type ClothingCategory,
  type ClothingItem,
} from '../lib/closet'

type SelectionMode = 'single' | 'multiple'

export function ClothingItemBrowser({
  allowEmptySelection = false,
  compact = false,
  emptySelectionLabel = 'No item selected',
  items,
  onSelectionChange,
  selectedItemIDs,
  selectionMode,
}: {
  allowEmptySelection?: boolean
  compact?: boolean
  emptySelectionLabel?: string
  items: ClothingItem[]
  onSelectionChange: (itemIDs: string[]) => void
  selectedItemIDs: string[]
  selectionMode: SelectionMode
}) {
  const inputGroupName = useId()
  const [searchTerm, setSearchTerm] = useState('')
  const [categoryFilter, setCategoryFilter] = useState<'all' | ClothingCategory>('all')
  const normalizedSearchTerm = searchTerm.trim().toLowerCase()
  const filteredItems = useMemo(
    () =>
      items.filter((item) => {
        const matchesCategory = categoryFilter === 'all' || item.category === categoryFilter
        const haystack = [
          item.name,
          item.brand,
          item.color,
          item.material,
          item.pattern,
          item.notes,
          categoryLabel(item.category),
        ]
          .join(' ')
          .toLowerCase()

        return matchesCategory && haystack.includes(normalizedSearchTerm)
      }),
    [categoryFilter, items, normalizedSearchTerm],
  )
  const groupedItems = useMemo(() => {
    const groups = new Map<ClothingCategory, ClothingItem[]>()

    filteredItems.forEach((item) => {
      const existingItems = groups.get(item.category) ?? []
      groups.set(item.category, [...existingItems, item])
    })

    return clothingCategories
      .map((category) => ({
        category,
        items: groups.get(category.value) ?? [],
      }))
      .filter((group) => group.items.length > 0)
  }, [filteredItems])

  function itemIsSelected(itemId: string) {
    return selectedItemIDs.includes(itemId)
  }

  function handleItemChange(itemId: string) {
    if (selectionMode === 'single') {
      onSelectionChange([itemId])
      return
    }

    onSelectionChange(
      itemIsSelected(itemId)
        ? selectedItemIDs.filter((selectedItemID) => selectedItemID !== itemId)
        : [...selectedItemIDs, itemId],
    )
  }

  return (
    <div className={`item-browser ${compact ? 'compact' : ''}`}>
      <div className="item-browser-controls">
        <label className="search-field">
          <Search size={18} aria-hidden="true" />
          <input
            onChange={(event) => setSearchTerm(event.target.value)}
            placeholder="Search clothing"
            type="search"
            value={searchTerm}
          />
        </label>
        <label className="form-field compact">
          <span>Type</span>
          <select
            onChange={(event) => setCategoryFilter(event.target.value as 'all' | ClothingCategory)}
            value={categoryFilter}
          >
            <option value="all">All types</option>
            {clothingCategories.map((category) => (
              <option key={category.value} value={category.value}>
                {category.label}
              </option>
            ))}
          </select>
        </label>
      </div>

      {allowEmptySelection && selectionMode === 'single' ? (
        <button
          type="button"
          className={`item-browser-empty ${selectedItemIDs.length === 0 ? 'selected' : ''}`}
          onClick={() => onSelectionChange([])}
        >
          {emptySelectionLabel}
        </button>
      ) : null}

      {groupedItems.length === 0 ? (
        <p className="helper-text">No clothing items match this search and type filter.</p>
      ) : null}

      <div className="item-browser-groups">
        {groupedItems.map((group) => {
          const hasSelection = group.items.some((item) => itemIsSelected(item.id))
          const shouldOpen = hasSelection || Boolean(normalizedSearchTerm) || categoryFilter !== 'all'

          return (
            <details className="item-browser-category" key={group.category.value} open={shouldOpen}>
              <summary>
                <span>{group.category.label}</span>
                <span>{group.items.length}</span>
              </summary>
              <div className="item-browser-items">
                {group.items.map((item) => (
                  <label className="closet-pick-row" key={item.id}>
                    <input
                      checked={itemIsSelected(item.id)}
                      name={selectionMode === 'single' ? inputGroupName : undefined}
                      onChange={() => handleItemChange(item.id)}
                      type={selectionMode === 'single' ? 'radio' : 'checkbox'}
                    />
                    <span>
                      <strong>{item.name}</strong>
                      <small>
                        {categoryLabel(item.category)}
                        {item.brand ? ` - ${item.brand}` : ''}
                        {item.material ? ` - ${item.material}` : ''}
                      </small>
                    </span>
                  </label>
                ))}
              </div>
            </details>
          )
        })}
      </div>
    </div>
  )
}
