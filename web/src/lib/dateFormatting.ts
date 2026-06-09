export function formatDateWithWeekday(value: string) {
  const date = parseDateOnlyUTC(value) ?? parseDateTime(value)

  if (!date) {
    return value
  }

  return new Intl.DateTimeFormat(undefined, {
    day: 'numeric',
    month: 'short',
    weekday: 'short',
    year: 'numeric',
    timeZone: isDateOnly(value) ? 'UTC' : undefined,
  }).format(date)
}

export function formatDateRangeWithWeekdays(startDate: string, endDate: string) {
  const startLabel = formatDateWithWeekday(startDate)
  const endLabel = formatDateWithWeekday(endDate)

  return startDate === endDate ? startLabel : `${startLabel} to ${endLabel}`
}

export function formatDateTimeWithWeekday(value: string) {
  const date = parseDateTime(value)

  if (!date) {
    return value
  }

  return new Intl.DateTimeFormat(undefined, {
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    month: 'short',
    weekday: 'short',
    year: 'numeric',
  }).format(date)
}

function isDateOnly(value: string) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value)
}

function parseDateOnlyUTC(value: string) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value)

  if (!match) {
    return null
  }

  const year = Number.parseInt(match[1], 10)
  const month = Number.parseInt(match[2], 10)
  const day = Number.parseInt(match[3], 10)
  const date = new Date(Date.UTC(year, month - 1, day))

  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return null
  }

  return date
}

function parseDateTime(value: string) {
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? null : date
}
