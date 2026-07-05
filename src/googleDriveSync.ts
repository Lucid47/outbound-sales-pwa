const googleIdentityScriptUrl = 'https://accounts.google.com/gsi/client'
const driveApiBaseUrl = 'https://www.googleapis.com/drive/v3'
const driveUploadBaseUrl = 'https://www.googleapis.com/upload/drive/v3'

export const driveAppDataScope = 'https://www.googleapis.com/auth/drive.appdata'
export const driveFileScope = 'https://www.googleapis.com/auth/drive.file'
export const googleProfileScope = 'openid email profile'
export const driveSyncFileName = 'outbound-sales-sync.json'

type TokenResponse = {
  access_token?: string
  error?: string
}

type TokenClient = {
  requestAccessToken: (options?: { prompt?: string }) => void
  callback: (response: TokenResponse) => void
}

type GoogleAccounts = {
  oauth2: {
    initTokenClient: (options: {
      client_id: string
      scope: string
      callback: (response: TokenResponse) => void
    }) => TokenClient
  }
}

declare global {
  interface Window {
    google?: {
      accounts: GoogleAccounts
    }
  }
}

type DriveFile = {
  id: string
  name: string
  modifiedTime?: string
}

type JsonPayload = Record<string, unknown>
export type GoogleUserProfile = {
  email: string
  name: string
  picture?: string
}

let googleIdentityPromise: Promise<void> | null = null
let tokenClient: TokenClient | null = null
let tokenScope = ''

export function isGoogleDriveSyncConfigured() {
  return Boolean(import.meta.env.VITE_GOOGLE_CLIENT_ID)
}

export async function requestGoogleDriveToken(scopes: string[], options: { prompt?: string } = {}) {
  const clientId = import.meta.env.VITE_GOOGLE_CLIENT_ID
  if (!clientId) throw new Error('missing-google-client-id')
  await loadGoogleIdentity()

  const scope = Array.from(new Set(scopes)).join(' ')
  return new Promise<string>((resolve, reject) => {
    const callback = (response: TokenResponse) => {
      if (response.error || !response.access_token) {
        reject(new Error(response.error || 'google-token-failed'))
        return
      }
      resolve(response.access_token)
    }

    if (!tokenClient || tokenScope !== scope) {
      tokenScope = scope
      tokenClient = window.google!.accounts.oauth2.initTokenClient({
        client_id: clientId,
        scope,
        callback,
      })
    } else {
      tokenClient.callback = callback
    }

    tokenClient.requestAccessToken(options.prompt === undefined ? undefined : { prompt: options.prompt })
  })
}

export async function getGoogleUserProfile(accessToken: string) {
  const response = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
    headers: { Authorization: `Bearer ${accessToken}` },
  })
  if (!response.ok) throw new Error('google-profile-failed')
  const profile = await response.json() as Partial<GoogleUserProfile>
  if (!profile.email) throw new Error('google-profile-missing-email')
  return {
    email: profile.email,
    name: profile.name || profile.email,
    picture: profile.picture,
  }
}

export async function findAppDataSyncFile(accessToken: string) {
  const query = new URLSearchParams({
    spaces: 'appDataFolder',
    fields: 'files(id,name,modifiedTime)',
    q: `name='${driveSyncFileName}' and trashed=false`,
  })
  const response = await driveFetch<{ files: DriveFile[] }>(accessToken, `${driveApiBaseUrl}/files?${query.toString()}`)
  return response.files[0] ?? null
}

export async function downloadDriveJson<T>(accessToken: string, fileId: string) {
  return driveFetch<T>(accessToken, `${driveApiBaseUrl}/files/${fileId}?alt=media`)
}

export async function createAppDataSyncFile(accessToken: string, payload: JsonPayload) {
  return uploadDriveJson(accessToken, driveSyncFileName, payload, { parents: ['appDataFolder'] })
}

export async function updateDriveJsonFile(accessToken: string, fileId: string, payload: JsonPayload) {
  const metadata = { name: driveSyncFileName, mimeType: 'application/json' }
  const body = multipartBody(metadata, payload)
  return driveFetch<DriveFile>(accessToken, `${driveUploadBaseUrl}/files/${fileId}?uploadType=multipart`, {
    method: 'PATCH',
    body,
  })
}

export async function createVisibleDriveBackup(accessToken: string, payload: JsonPayload) {
  const date = new Date().toISOString().slice(0, 10)
  return uploadDriveJson(accessToken, `영업도우미-백업-${date}.json`, payload)
}

async function uploadDriveJson(accessToken: string, name: string, payload: JsonPayload, metadataExtra: Record<string, unknown> = {}) {
  const metadata = { name, mimeType: 'application/json', ...metadataExtra }
  const body = multipartBody(metadata, payload)
  return driveFetch<DriveFile>(accessToken, `${driveUploadBaseUrl}/files?uploadType=multipart&fields=id,name,modifiedTime`, {
    method: 'POST',
    body,
  })
}

function multipartBody(metadata: Record<string, unknown>, payload: JsonPayload) {
  const boundary = `outbound-sales-${crypto.randomUUID()}`
  const delimiter = `\r\n--${boundary}\r\n`
  const closeDelimiter = `\r\n--${boundary}--`
  const body = [
    delimiter,
    'Content-Type: application/json; charset=UTF-8\r\n\r\n',
    JSON.stringify(metadata),
    delimiter,
    'Content-Type: application/json; charset=UTF-8\r\n\r\n',
    JSON.stringify(payload),
    closeDelimiter,
  ].join('')

  return new Blob([body], { type: `multipart/related; boundary=${boundary}` })
}

async function driveFetch<T>(accessToken: string, url: string, init: RequestInit = {}) {
  const response = await fetch(url, {
    ...init,
    headers: {
      ...init.headers,
      Authorization: `Bearer ${accessToken}`,
    },
  })
  if (!response.ok) {
    throw new Error(`drive-api-failed-${response.status}`)
  }
  return await response.json() as T
}

function loadGoogleIdentity() {
  if (window.google?.accounts) return Promise.resolve()
  if (googleIdentityPromise) return googleIdentityPromise

  googleIdentityPromise = new Promise((resolve, reject) => {
    const script = document.createElement('script')
    script.src = googleIdentityScriptUrl
    script.async = true
    script.defer = true
    script.onload = () => resolve()
    script.onerror = () => reject(new Error('google-identity-load-failed'))
    document.head.append(script)
  })

  return googleIdentityPromise
}
