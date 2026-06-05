import type { OutfitScoreBreakdown, ScoreBreakdownComponent } from '../lib/outfits'

export function ScoreDebugPanel({
  breakdown,
  title = 'Score Debug',
}: {
  breakdown?: OutfitScoreBreakdown
  title?: string
}) {
  if (!breakdown) {
    return (
      <details className="score-debug-panel">
        <summary>{title}</summary>
        <p className="helper-text">
          This outfit was saved before detailed score debugging existed. Regenerate or rescore it
          to see the full breakdown.
        </p>
      </details>
    )
  }

  return (
    <details className="score-debug-panel">
      <summary>{title}</summary>
      <div className="score-debug-summary">
        <span>
          <strong>{breakdown.startingScore}</strong>
          Base
        </span>
        <span>
          <strong>{breakdown.rawScore}</strong>
          Raw
        </span>
        <span>
          <strong>{breakdown.finalScore}</strong>
          Final
        </span>
      </div>

      <section className="score-debug-section">
        <h3>Outfit Math</h3>
        <ScoreComponentList components={breakdown.outfitComponents} />
      </section>

      <section className="score-debug-section">
        <h3>Item Math</h3>
        <div className="score-debug-items">
          {breakdown.itemBreakdowns.map((item) => (
            <details className="score-debug-item" key={item.itemID || item.itemName}>
              <summary>
                <span>
                  <strong>{item.itemName}</strong>
                  <small>{item.categoryLabel}</small>
                </span>
                <span className={deltaClass(item.contributionToOutfit)}>
                  {deltaText(item.contributionToOutfit)}
                </span>
              </summary>
              <p className="helper-text">
                Item score {item.rawScore}/100 became {deltaText(item.contributionToOutfit)} on
                the outfit score.
              </p>
              <ScoreComponentList components={item.components} />
            </details>
          ))}
        </div>
      </section>
    </details>
  )
}

function ScoreComponentList({ components }: { components: ScoreBreakdownComponent[] }) {
  if (components.length === 0) {
    return <p className="helper-text">No detailed score components recorded.</p>
  }

  return (
    <div className="score-component-list">
      {components.map((component, index) => (
        <div className="score-component-row" key={`${component.label}-${index}`}>
          <span className={deltaClass(component.delta)}>{deltaText(component.delta)}</span>
          <span>{component.label}</span>
          <small>{component.scoreAfter}</small>
        </div>
      ))}
    </div>
  )
}

function deltaText(delta: number) {
  if (delta > 0) {
    return `+${formatNumber(delta)}`
  }

  return formatNumber(delta)
}

function deltaClass(delta: number) {
  if (delta > 0) {
    return 'score-delta positive'
  }

  if (delta < 0) {
    return 'score-delta negative'
  }

  return 'score-delta neutral'
}

function formatNumber(value: number) {
  return Number.isInteger(value) ? `${value}` : value.toFixed(1)
}
