export type OutfitContext = string

export type OutfitContextOption = {
  value: OutfitContext
  label: string
  description: string
}

export const outfitContexts: OutfitContextOption[] = [
  {
    value: 'work',
    label: 'Work',
    description:
      'Professional or semi-professional outfits for office days, meetings, briefings, TDY admin, and work travel. Favor collared shirts, blouses, polos, chinos, trousers, skirts, clean shoes, simple layers, and restrained accessories.',
  },
  {
    value: 'travel',
    label: 'Travel',
    description:
      'Airport, road trip, train, hotel transit, and long movement days. Favor comfortable but presentable pieces, wrinkle-resistant tops, breathable pants, soft layers, easy shoes, and outfits that still look decent after sitting for hours.',
  },
  {
    value: 'casual',
    label: 'Casual',
    description:
      'Normal everyday outfits for errands, coffee, shopping, family visits, breweries, casual hangs, and off-duty wear. Favor tees, polos, henleys, casual tops, jeans, chinos, shorts, casual dresses, sneakers, sandals, and relaxed layers.',
  },
  {
    value: 'coastalCasual',
    label: 'Coastal Casual',
    description:
      'Florida/Destin-style relaxed outfits where flip flops, shorts, T-shirts, and tank tops are acceptable. Use for beach-town errands, pool-adjacent outfits, casual outdoor meals, relaxed warm-weather days, and very low-key settings. Favor shorts, tanks, T-shirts, sandals, flip flops, linen/cotton tops, and swimsuit-adjacent casual pieces.',
  },
  {
    value: 'lounge',
    label: 'Lounge',
    description:
      'Comfort-first outfits for home, hotel rooms, low-energy days, reading, relaxing, stretching, or casual indoor time. Favor sweatpants, joggers, hoodies, leggings, soft shorts, T-shirts, slides, sneakers, and cozy layers.',
  },
  {
    value: 'goingOut',
    label: 'Going Out',
    description:
      'Date night, nice dinner, rooftop drinks, bars, concerts, parties, and social evenings. Favor sharper tops, fitted or elevated pieces, darker or more intentional colors, dresses, skirts, nicer pants, polished shoes, jewelry, watches, and intentional accessories.',
  },
  {
    value: 'exploring',
    label: 'Exploring',
    description:
      'Sightseeing, museums, downtown walking, markets, mountain towns, vacation wandering, and photo-friendly daytime plans. Favor walkable shoes, breathable tops, comfortable pants or shorts, casual dresses, practical layers, sunglasses, hats, and outfits that look good in photos but can handle several hours of walking.',
  },
  {
    value: 'outdoorRecreation',
    label: 'Outdoor Recreation',
    description:
      'Hiking, beach walks, parks, light adventure, mountain activities, lake days, and casual outdoor movement that is not a formal workout. Favor practical outdoor clothes, sun protection, layers, sturdy footwear, breathable fabrics, and clothes that can get a little dusty, sandy, or sweaty.',
  },
  {
    value: 'lifting',
    label: 'Lifting',
    description:
      'Strength training, hotel lifting, circuits, mobility, and bodyweight workouts. Favor athletic tops, tanks, sports bras, workout shorts, leggings, joggers, and training shoes. Prioritize range of motion and gym functionality.',
  },
  {
    value: 'running',
    label: 'Running',
    description:
      'Easy runs, speed workouts, treadmill runs, recovery jogs, outdoor runs, and run/walk sessions. Favor running-specific shorts, leggings, breathable tops, sports bras, running socks, running shoes, hats, sunglasses, and reflective gear when appropriate.',
  },
]

export function normalizeOutfitContext(value: unknown): OutfitContext {
  const rawValue = String(value ?? '').trim()
  const compactValue = compactContextValue(rawValue)

  switch (compactValue) {
    case 'work':
    case 'workoffice':
    case 'office':
    case 'business':
    case 'businesscasual':
    case 'pilot':
    case 'pilotwork':
      return 'work'
    case 'travel':
    case 'travelday':
    case 'airport':
    case 'transit':
      return 'travel'
    case 'casual':
    case 'casualday':
    case 'everyday':
    case 'everydaycasual':
    case 'streetcasual':
    case 'smartcasual':
      return 'casual'
    case 'coastalcasual':
    case 'floridacasual':
    case 'destin':
    case 'beachcasual':
      return 'coastalCasual'
    case 'lounge':
    case 'loungewear':
    case 'home':
    case 'hotel':
      return 'lounge'
    case 'goingout':
    case 'dinner':
    case 'dinnerdate':
    case 'date':
    case 'datenight':
    case 'nightout':
      return 'goingOut'
    case 'exploring':
    case 'sightseeing':
    case 'walking':
    case 'walkingaroundcity':
      return 'exploring'
    case 'outdoorrecreation':
    case 'outdoor':
    case 'hiking':
    case 'lightadventure':
      return 'outdoorRecreation'
    case 'lifting':
    case 'gym':
    case 'strength':
    case 'training':
    case 'workout':
      return 'lifting'
    case 'running':
    case 'run':
    case 'jog':
    case 'jogging':
      return 'running'
    case 'hot':
    case 'hotweather':
    case 'cold':
    case 'coldweather':
    case 'rain':
    case 'rainy':
    case 'rainyweather':
    case 'snow':
    case 'snowy':
    case 'snowyweather':
      return 'casual'
    default:
      return rawValue || 'casual'
  }
}

export function contextSlug(label: string) {
  const words = label
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .split(' ')
    .filter(Boolean)

  if (words.length === 0) {
    return `custom-${crypto.randomUUID()}`
  }

  return words
    .map((word, index) => (index === 0 ? word : `${word[0].toUpperCase()}${word.slice(1)}`))
    .join('')
}

export function isDefaultOutfitContext(context: OutfitContext) {
  return outfitContexts.some((option) => option.value === context)
}

export function defaultContextLabel(context: OutfitContext) {
  return outfitContexts.find((option) => option.value === context)?.label ?? humanizeContext(context)
}

export function defaultContextDescription(context: OutfitContext) {
  return outfitContexts.find((option) => option.value === context)?.description ?? ''
}

function humanizeContext(context: OutfitContext) {
  return context
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/[-_]+/g, ' ')
    .replace(/\b\w/g, (match) => match.toUpperCase())
}

function compactContextValue(value: string) {
  return value.toLowerCase().replace(/[^a-z]/g, '')
}
