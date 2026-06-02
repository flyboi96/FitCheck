export type EncodedImage = {
  base64: string
  mimeType: string
}

const firestoreImageMaxBase64Length = 850_000

export async function imageFileToBase64(
  file: File,
  maxDimension = 1400,
  quality = 0.84,
): Promise<EncodedImage> {
  const dataURL = await readFileAsDataURL(file)
  const image = await loadImage(dataURL)
  const scale = Math.min(1, maxDimension / Math.max(image.width, image.height))
  const width = Math.max(1, Math.round(image.width * scale))
  const height = Math.max(1, Math.round(image.height * scale))
  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height

  const context = canvas.getContext('2d')
  if (!context) {
    return dataURLToEncodedImage(dataURL, file.type || 'image/jpeg')
  }

  context.drawImage(image, 0, 0, width, height)
  const mimeType = file.type === 'image/png' ? 'image/png' : 'image/jpeg'
  const compressedDataURL = canvas.toDataURL(mimeType, quality)
  return dataURLToEncodedImage(compressedDataURL, mimeType)
}

export async function compactEncodedImageForFirestore(
  image: EncodedImage,
  {
    maxBase64Length = firestoreImageMaxBase64Length,
    maxDimension = 900,
    minDimension = 480,
    quality = 0.78,
  }: {
    maxBase64Length?: number
    maxDimension?: number
    minDimension?: number
    quality?: number
  } = {},
): Promise<EncodedImage> {
  const sourceDataURL = encodedImageToDataURL(image)
  let nextDimension = maxDimension
  let nextQuality = quality
  let bestImage: EncodedImage | null = null

  for (let attempt = 0; attempt < 8; attempt += 1) {
    const compactImage = await resizeDataURLToEncodedImage(
      sourceDataURL,
      nextDimension,
      nextQuality,
      'image/jpeg',
    )

    bestImage = compactImage

    if (compactImage.base64.length <= maxBase64Length) {
      return compactImage
    }

    nextDimension = Math.max(minDimension, Math.round(nextDimension * 0.82))
    nextQuality = Math.max(0.52, nextQuality - 0.07)
  }

  if (!bestImage || bestImage.base64.length > maxBase64Length) {
    throw new Error('Avatar image is still too large to save. Use a smaller or less detailed image.')
  }

  return bestImage
}

export function encodedImageToDataURL(image: EncodedImage) {
  return `data:${image.mimeType};base64,${image.base64}`
}

function readFileAsDataURL(file: File) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(String(reader.result ?? ''))
    reader.onerror = () => reject(reader.error ?? new Error('Could not read image.'))
    reader.readAsDataURL(file)
  })
}

async function resizeDataURLToEncodedImage(
  dataURL: string,
  maxDimension: number,
  quality: number,
  mimeType: string,
) {
  const image = await loadImage(dataURL)
  const scale = Math.min(1, maxDimension / Math.max(image.width, image.height))
  const width = Math.max(1, Math.round(image.width * scale))
  const height = Math.max(1, Math.round(image.height * scale))
  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height

  const context = canvas.getContext('2d')
  if (!context) {
    return dataURLToEncodedImage(dataURL, mimeType)
  }

  context.fillStyle = '#ffffff'
  context.fillRect(0, 0, width, height)
  context.drawImage(image, 0, 0, width, height)

  return dataURLToEncodedImage(canvas.toDataURL(mimeType, quality), mimeType)
}

function loadImage(dataURL: string) {
  return new Promise<HTMLImageElement>((resolve, reject) => {
    const image = new Image()
    image.onload = () => resolve(image)
    image.onerror = () => reject(new Error('Could not load image.'))
    image.src = dataURL
  })
}

function dataURLToEncodedImage(dataURL: string, fallbackMimeType: string): EncodedImage {
  const [metadata, base64 = ''] = dataURL.split(',')
  const mimeType = metadata.match(/^data:(.*?);base64$/)?.[1] || fallbackMimeType
  return {
    base64,
    mimeType,
  }
}
