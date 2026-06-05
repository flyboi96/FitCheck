import {
  categoryLabel,
  type ClothingItem,
} from './closet'
import type { WearerProfile } from './profile'

export type ClosetSetupTask = {
  id: string
  title: string
  description: string
  done: boolean
  count: number
}

export type ClothingItemInsight = {
  bestContexts: string[]
  metadataPrompts: string[]
  rewearGuidance: string
  weatherUse: string
}

export function closetSetupTasks(items: ClothingItem[]): ClosetSetupTask[] {
  const activeItems = items.filter((item) => item.status === 'active')

  return [
    {
      id: 'daily-base',
      title: 'Everyday Base',
      description: 'At least one top, bottom, shoes, socks, and underwear for normal outfit generation.',
      done:
        hasRole(activeItems, 'top') &&
        hasRole(activeItems, 'bottom') &&
        hasRole(activeItems, 'shoes') &&
        activeItems.some((item) => item.category === 'socks') &&
        activeItems.some((item) => item.category === 'underwear'),
      count: activeItems.length,
    },
    {
      id: 'work',
      title: 'Work Capsule',
      description: 'Collared or polished tops, presentable bottoms, clean shoes, and belt if you wear belt-loop pants.',
      done:
        activeItems.some((item) => /button|collar|polo|blouse|oxford/.test(itemText(item))) &&
        activeItems.some((item) => /chino|trouser|pant|skirt|dress/.test(itemText(item))) &&
        activeItems.some((item) => /boot|loafer|flat|heel|dress shoe|leather/.test(itemText(item))),
      count: activeItems.filter((item) => bestContextsForItem(item).includes('Work')).length,
    },
    {
      id: 'casual',
      title: 'Casual Capsule',
      description: 'Comfortable everyday tops, shorts/pants, and casual shoes for errands and off-duty wear.',
      done:
        activeItems.some((item) => /tee|t-shirt|henley|polo|shirt/.test(itemText(item))) &&
        activeItems.some((item) => /short|jean|chino|pant/.test(itemText(item))) &&
        activeItems.some((item) => /sneaker|sandal|casual/.test(itemText(item))),
      count: activeItems.filter((item) => bestContextsForItem(item).includes('Casual')).length,
    },
    {
      id: 'workout',
      title: 'Workout Gear',
      description: 'Exercise tops, bottoms, socks, and training or running shoes.',
      done:
        activeItems.some((item) => /activewear|gym|training|lifting|running|workout|dri/.test(itemText(item))) &&
        activeItems.some((item) => /trainer|training shoe|running shoe|runner/.test(itemText(item))) &&
        activeItems.some((item) => item.category === 'socks' && /run|athletic|lifting|gym/.test(itemText(item))),
      count: activeItems.filter((item) => bestContextsForItem(item).some((context) => /Running|Lifting/.test(context))).length,
    },
    {
      id: 'weather',
      title: 'Weather Coverage',
      description: 'Light heat-friendly items, rain-ready layer if you own one, and a cooler-weather layer.',
      done:
        activeItems.some(isHeatFriendly) &&
        activeItems.some((item) => /rain|shell|waterproof|water resistant|storm/.test(itemText(item))) &&
        activeItems.some((item) => /jacket|sweater|layer|fleece|wool/.test(itemText(item))),
      count: activeItems.filter((item) => weatherUseForItem(item) !== 'General weather use').length,
    },
  ]
}

export function clothingItemInsight(item: ClothingItem): ClothingItemInsight {
  const bestContexts = bestContextsForItem(item)
  const metadataPrompts = [
    item.brand.trim() ? '' : 'Add brand',
    item.material.trim() ? '' : 'Add material',
    item.color.trim() ? '' : 'Add color',
    item.notes.trim() ? '' : 'Add fit/weather notes',
  ].filter(Boolean)

  return {
    bestContexts: bestContexts.length > 0 ? bestContexts : ['General'],
    metadataPrompts,
    rewearGuidance: rewearGuidanceForItem(item),
    weatherUse: weatherUseForItem(item),
  }
}

export function starterClosetImportTemplate(wearerProfile: WearerProfile) {
  const sharedLines = [
    '7x everyday underwear | underwear |  | cotton or synthetic blend',
    '7x everyday socks | socks |  | cotton or athletic blend',
    '2x athletic socks | socks |  | synthetic performance | running/lifting',
    'white sneakers | shoes |  | leather or canvas | casual/exploring',
    'comfortable travel sneakers | shoes |  | breathable | airport and walking days',
    'light rain shell | jacket |  | waterproof | rain without warmth',
    'lightweight sweater or layer | sweater |  | merino or fleece | cool evenings/travel',
  ]
  const maleLines = [
    'light blue short sleeve button-down shirt | shirt |  | performance or cotton | work/travel',
    'white cotton T-shirt | shirt |  | cotton | casual/coastal',
    'salmon henley short sleeve shirt | shirt |  | cotton | casual bold item',
    'beige chino pants | pants |  | cotton or merino | work/travel',
    'khaki chino shorts | shorts |  | cotton | casual/coastal',
    'brown leather belt | belt |  | leather | work with collared shirts',
    'brown leather boots | shoes |  | leather | work/going out',
    '2x workout shirt | activewear |  | synthetic performance | lifting/running',
    '2x workout shorts | activewear |  | synthetic performance | lifting/running',
    'running shoes | shoes |  | performance | running only',
  ]
  const femaleLines = [
    'white cotton T-shirt | shirt |  | cotton | casual/coastal',
    'polished blouse | blouse |  | cotton or silk blend | work/going out',
    'casual dress | dress |  | cotton or linen | casual/coastal',
    'work trousers | pants |  | stretch woven | work/travel',
    'casual shorts | shorts |  | cotton or linen | casual/coastal',
    'comfortable flats | flats |  | leather or knit | work/travel',
    'polished sandals | shoes |  | leather | coastal/going out',
    '2x workout top | activewear |  | synthetic performance | lifting/running',
    '2x workout leggings or shorts | activewear |  | synthetic performance | lifting/running',
    'running shoes | shoes |  | performance | running only',
  ]

  return [...(wearerProfile === 'female' ? femaleLines : maleLines), ...sharedLines].join('\n')
}

function bestContextsForItem(item: ClothingItem) {
  const text = itemText(item)
  const contexts: string[] = []

  if (/button|collar|polo|blouse|chino|trouser|loafer|boot|belt|dress|skirt|flat|heel/.test(text)) {
    contexts.push('Work')
  }
  if (/travel|wrinkle|stretch|comfortable|sneaker|chino|soft|layer/.test(text)) {
    contexts.push('Travel')
  }
  if (/tee|t-shirt|henley|jean|short|sneaker|casual|cotton/.test(text)) {
    contexts.push('Casual')
  }
  if (/flip|sandal|linen|tank|short|beach|swim|coastal/.test(text)) {
    contexts.push('Coastal Casual')
  }
  if (/sweat|jogger|hoodie|lounge|soft|slide|slipper/.test(text)) {
    contexts.push('Lounge')
  }
  if (/dark|fitted|dress|jewelry|watch|leather|boot|heel|blouse|sweater/.test(text)) {
    contexts.push('Going Out')
  }
  if (/walk|sneaker|hat|sunglass|breathable|short|travel/.test(text)) {
    contexts.push('Exploring')
  }
  if (/hiking|trail|outdoor|sun|water|beach|lake|sturdy/.test(text)) {
    contexts.push('Outdoor Recreation')
  }
  if (/lifting|training|gym|workout|trainer|mobility/.test(text)) {
    contexts.push('Lifting')
  }
  if (/run|running|runner|reflective/.test(text)) {
    contexts.push('Running')
  }

  return [...new Set(contexts)]
}

function rewearGuidanceForItem(item: ClothingItem) {
  if (item.category === 'underwear' || item.category === 'socks') {
    return 'Wash after each wear'
  }

  if (item.category === 'activewear') {
    return 'Wash after sweaty workouts'
  }

  if (item.category === 'shirt' || item.category === 'blouse') {
    return 'Usually 1 wear before wash'
  }

  if (item.category === 'pants' || item.category === 'shorts' || item.category === 'skirt') {
    return 'Often 2-4 wears if clean'
  }

  if (
    item.category === 'belt' ||
    item.category === 'watch' ||
    item.category === 'jewelry' ||
    item.category === 'bag' ||
    item.category === 'purse'
  ) {
    return 'Can rewear freely'
  }

  if (item.category === 'jacket' || item.category === 'sweater' || item.category === 'shoes') {
    return 'Rewear often unless dirty'
  }

  return 'Use normal laundry judgment'
}

function weatherUseForItem(item: ClothingItem) {
  const text = itemText(item)
  const tags: string[] = []

  if (isHeatFriendly(item)) tags.push('hot weather')
  if (/rain|shell|waterproof|water resistant|storm/.test(text)) tags.push('rain')
  if (/wool|fleece|sweater|jacket|layer|boot/.test(text)) tags.push('cool weather')
  if (/wind|windbreaker/.test(text)) tags.push('wind')

  return tags.length > 0 ? tags.join(', ') : 'General weather use'
}

function hasRole(items: ClothingItem[], role: 'top' | 'bottom' | 'shoes') {
  return items.some((item) => {
    if (role === 'top') {
      return ['shirt', 'blouse', 'sweater', 'activewear'].includes(item.category)
    }
    if (role === 'bottom') {
      return ['pants', 'shorts', 'skirt', 'activewear'].includes(item.category)
    }
    return ['shoes', 'heels', 'flats'].includes(item.category)
  })
}

function itemText(item: ClothingItem) {
  return [
    item.name,
    item.brand,
    item.color,
    item.material,
    item.pattern,
    categoryLabel(item.category),
    item.notes,
  ]
    .join(' ')
    .toLowerCase()
}

function isHeatFriendly(item: ClothingItem) {
  return /linen|cotton|dri|dry|tech|performance|short sleeve|t-shirt|tee|shorts|lightweight|breathable/.test(
    itemText(item),
  )
}
