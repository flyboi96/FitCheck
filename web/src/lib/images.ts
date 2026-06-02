export type EncodedImage = {
  base64: string
  mimeType: string
}

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

function readFileAsDataURL(file: File) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(String(reader.result ?? ''))
    reader.onerror = () => reject(reader.error ?? new Error('Could not read image.'))
    reader.readAsDataURL(file)
  })
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
