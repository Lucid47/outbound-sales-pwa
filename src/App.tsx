import { useEffect, useMemo, useRef, useState } from 'react'
import Papa from 'papaparse'
import { useMap } from 'react-leaflet'
import { MapContainer, Marker, Polyline, Popup, TileLayer } from 'react-leaflet'
import L from 'leaflet'
import {
  CalendarCheck,
  Check,
  Cloud,
  Clipboard,
  Download,
  FileSpreadsheet,
  LayoutGrid,
  List,
  ListFilter,
  LogOut,
  MessageSquareText,
  Navigation,
  Pencil,
  PhoneCall,
  Plus,
  RefreshCw,
  RotateCcw,
  Route,
  Save,
  Search,
  Settings,
  Trash2,
  Upload,
  UserRound,
} from 'lucide-react'
import 'leaflet/dist/leaflet.css'
import {
  appDb,
  type ContactLog,
  type Customer,
  type CustomerList,
  type MessageTemplate,
  type VisitLog,
  type VisitSchedule,
  type VisitScheduleItem,
} from './db/appDb'
import {
  createAppDataSyncFile,
  createVisibleDriveBackup,
  downloadDriveJson,
  driveAppDataScope,
  driveFileScope,
  findAppDataSyncFile,
  getGoogleUserProfile,
  googleProfileScope,
  isGoogleDriveSyncConfigured,
  requestGoogleDriveToken,
  updateDriveJsonFile,
  type GoogleUserProfile,
} from './googleDriveSync'
import './App.css'

type TabKey = 'today' | 'customers' | 'import' | 'logs' | 'settings'
type TodayMode = 'schedule' | 'nearest' | 'region' | 'map'
type ListFilterKey = 'open' | 'done' | 'all' | 'age'
type DisplayMode = 'cards' | 'list'
type BeforeInstallPromptEvent = Event & {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed'; platform: string }>
}
type GeocodeProgress = {
  running: boolean
  done: number
  total: number
  failed: number
  current: string
}
type CustomerForm = {
  name: string
  phoneNumber: string
  address: string
  birthDate: string
  notes: string
}

type MetricSheet = {
  title: string
  customers: Customer[]
}

type ParsedCsv = {
  headers: string[]
  rows: string[][]
  mapping: FieldMapping
}

type FieldKey = 'name' | 'phoneNumber' | 'address' | 'birthDate' | 'notes' | 'latitude' | 'longitude'
type FieldMapping = Record<FieldKey, number | null>
type AppBackupPayload = {
  schemaVersion?: number
  exportedAt?: string
  customerLists?: CustomerList[]
  customers?: Customer[]
  visitLogs?: VisitLog[]
  contactLogs?: ContactLog[]
  visitSchedules?: VisitSchedule[]
  visitScheduleItems?: VisitScheduleItem[]
  messageTemplates?: MessageTemplate[]
}
type GoogleDriveAccount = GoogleUserProfile & {
  connectedAt: string
}

const installGuideDismissedKey = 'installGuideDismissed'
const lastDriveSyncAtKey = 'lastDriveSyncAt'
const lastLocalChangeAtKey = 'lastLocalChangeAt'
const googleDriveAccountKey = 'googleDriveAccount'
const displayModeKey = 'displayMode'
const defaultCenter: [number, number] = [37.5009, 127.0364]
const userLocationIcon = L.divIcon({
  className: 'user-location-pin',
  html: '<span></span>',
  iconSize: [32, 44],
  iconAnchor: [16, 44],
  popupAnchor: [0, -42],
})

function customerMapIcon(customer: Customer, selected: boolean, scheduled: boolean) {
  const statusClass = customer.status === 'done' ? 'done' : scheduled ? 'scheduled' : 'open'
  const statusLabel = customer.status === 'done' ? '완료' : scheduled ? '예정' : '미완'
  const shortName = customer.name.length > 7 ? `${customer.name.slice(0, 7)}…` : customer.name
  return L.divIcon({
    className: `customer-map-label ${statusClass} ${selected ? 'selected' : ''}`,
    html: `<span class="name">${shortName}</span><span class="state">${statusLabel}</span>`,
    iconSize: [92, 34],
    iconAnchor: [46, 17],
    popupAnchor: [0, -18],
  })
}

const aliases: Record<FieldKey, string[]> = {
  name: ['고객명', '고객 이름', '이름', '성명', '거래처명', '회사명', 'name', 'customer', 'customername'],
  phoneNumber: ['연락처', '전화번호', '휴대폰', '핸드폰', '휴대전화', 'mobile', 'phone', 'tel', 'telephone'],
  address: ['주소', '우편물주소', '우편주소', '방문주소', '사업장주소', '고객주소', 'address', 'addr', 'location'],
  birthDate: ['생년월일', '생일', '출생일', '출생년도', '생년', 'birth', 'birthday', 'birthdate', 'dateofbirth', 'dob'],
  notes: ['메모', '비고', '기타', '기타사항', '담당자메모', 'notes', 'note', 'memo', 'remark'],
  latitude: ['위도', 'lat', 'latitude', 'y', 'goaly'],
  longitude: ['경도', 'lng', 'lon', 'long', 'longitude', 'x', 'goalx'],
}

const sampleLists: CustomerList[] = [
  {
    id: 'list-a',
    name: '고객사 A - 7월 방문 리스트',
    companyName: '고객사 A',
    sourceFileName: 'customer_a_july.csv',
    importedAt: '2026-07-03T09:12:00+09:00',
    createdAt: '2026-07-03T09:12:00+09:00',
    updatedAt: '2026-07-03T09:12:00+09:00',
  },
  {
    id: 'list-b',
    name: '고객사 B - 신규 리드',
    companyName: '고객사 B',
    sourceFileName: 'customer_b_new.csv',
    importedAt: '2026-07-02T16:40:00+09:00',
    createdAt: '2026-07-02T16:40:00+09:00',
    updatedAt: '2026-07-02T16:40:00+09:00',
  },
]

const sampleCustomers: Customer[] = [
  makeCustomer('c-1', 'list-a', '홍길동', '010-1234-5678', '서울 강남구 테헤란로 152', '오후 방문 선호', 37.5012, 127.0396, '강남구 역삼동'),
  makeCustomer('c-2', 'list-a', '김영희', '010-2468-1357', '서울 강남구 봉은사로 114', '계약서 재안내', 37.5064, 127.0317, '강남구 역삼동'),
  makeCustomer('c-3', 'list-a', '박민수', '010-7777-9911', '서울 강남구 삼성로 534', '대표 부재 잦음', 37.5109, 127.0598, '강남구 삼성동', 'done'),
  makeCustomer('c-4', 'list-a', '이지훈', '010-5555-1204', '서울 서초구 서초대로 396', '주차 가능', 37.4973, 127.0246, '서초구 서초동'),
  makeCustomer('c-5', 'list-a', '최수진', '010-9090-3434', '서울 강남구 도산대로 150', '다음 주 재방문 가능', 37.5193, 127.0247, '강남구 신사동', 'hold'),
  makeCustomer('c-6', 'list-b', '오세훈', '010-2222-8800', '서울 마포구 양화로 45', '신규 상담', 37.5507, 126.9141, '마포구 서교동'),
  makeCustomer('c-7', 'list-b', '문하린', '010-3333-8801', '서울 영등포구 국제금융로 10', '오후 3시 이후', 37.5251, 126.9244, '영등포구 여의도동'),
  makeCustomer('c-8', 'list-b', '서민재', '010-3333-8802', '서울 용산구 한강대로 100', '자료 문자 선호', 37.5296, 126.9646, '용산구 한강로동', 'done'),
]

const sampleSchedules: VisitSchedule[] = [
  makeSchedule('schedule-a', 'list-a', '고객사 A 오늘 방문'),
  makeSchedule('schedule-b', 'list-b', '고객사 B 오늘 방문'),
]

const sampleScheduleItems: VisitScheduleItem[] = []

const sampleVisitLogs: VisitLog[] = [
  {
    id: 'visit-1',
    customerListId: 'list-a',
    customerId: 'c-3',
    visitedAt: '2026-07-03T13:10:00+09:00',
    result: 'completed',
    memo: '초기 샘플 방문 기록',
    createdAt: '2026-07-03T13:10:00+09:00',
  },
  {
    id: 'visit-2',
    customerListId: 'list-b',
    customerId: 'c-8',
    visitedAt: '2026-07-02T15:40:00+09:00',
    result: 'completed',
    memo: '초기 샘플 방문 기록',
    createdAt: '2026-07-02T15:40:00+09:00',
  },
]

const defaultTemplates: MessageTemplate[] = [
  makeTemplate('tpl-1', '방문 상담 안내', '안녕하세요, {고객명}님. 방문 상담차 연락드렸습니다. 가능하실 때 회신 부탁드립니다.', true),
  makeTemplate('tpl-2', '도착 전 연락', '안녕하세요, {고객명}님. 근처에 도착하여 연락드립니다. 잠시 후 뵙겠습니다.'),
  makeTemplate('tpl-3', '재방문 문의', '안녕하세요, {고객명}님. 다시 방문 가능한 시간을 확인하고 싶어 연락드립니다.'),
]

const notePresets = [
  '전화하였으나 받지 않음',
  '문자로 연락함',
  '방문하였으나 부재',
  '사용자 템플릿: ',
]

function makeCustomer(
  id: string,
  customerListId: string,
  name: string,
  phoneNumber: string,
  address: string,
  notes: string,
  latitude: number,
  longitude: number,
  region: string,
  status: Customer['status'] = 'open',
): Customer {
  const now = new Date().toISOString()
  return { id, customerListId, name, phoneNumber, address, notes, latitude, longitude, coordinateSource: 'sample', region, status, createdAt: now, updatedAt: now }
}

function makeSchedule(id: string, customerListId: string, title: string): VisitSchedule {
  const now = new Date().toISOString()
  return { id, customerListId, title, date: todayKey(), createdAt: now, updatedAt: now }
}

function makeTemplate(id: string, title: string, body: string, isDefault = false): MessageTemplate {
  const now = new Date().toISOString()
  return { id, title, body, isDefault, createdAt: now, updatedAt: now }
}

function todayKey() {
  return new Date().toISOString().slice(0, 10)
}

function makeId(prefix: string) {
  return `${prefix}-${crypto.randomUUID()}`
}

function normalizeHeader(value: string) {
  return value.trim().toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '').replace(/\d+$/, '')
}

function detectMapping(headers: string[]): FieldMapping {
  const mapping: FieldMapping = { name: null, phoneNumber: null, address: null, birthDate: null, notes: null, latitude: null, longitude: null }
  headers.forEach((header, index) => {
    const normalized = normalizeHeader(header)
    ;(Object.keys(aliases) as FieldKey[]).forEach((field) => {
      if (mapping[field] !== null) return
      if (aliases[field].map(normalizeHeader).includes(normalized)) {
        mapping[field] = index
      }
    })
  })
  return mapping
}

function cleanPhone(phoneNumber: string) {
  const trimmed = phoneNumber.trim()
  const digits = trimmed.replace(/\D/g, '')
  return trimmed.startsWith('+') ? `+${digits}` : digits
}

function hasDialablePhone(phoneNumber: string) {
  return cleanPhone(phoneNumber).replace(/\D/g, '').length >= 7
}

function parseCoordinate(value: string, kind: 'latitude' | 'longitude') {
  const normalized = value.trim().replace(',', '.')
  if (!normalized) return undefined
  const coordinate = Number(normalized)
  if (!Number.isFinite(coordinate)) return undefined
  if (kind === 'latitude' && coordinate >= -90 && coordinate <= 90) return coordinate
  if (kind === 'longitude' && coordinate >= -180 && coordinate <= 180) return coordinate
  return undefined
}

function extractRegion(address: string) {
  const normalized = normalizeAddressText(address)
  const parts = normalized.split(' ').filter(Boolean)
  let districtIndex = -1
  for (let index = parts.length - 1; index >= 0; index -= 1) {
    if (/(?:구|군)$/.test(parts[index])) {
      districtIndex = index
      break
    }
  }
  const cityIndex = districtIndex === -1 ? parts.findIndex((part) => /시$/.test(part)) : -1
  const baseIndex = districtIndex !== -1 ? districtIndex : cityIndex
  if (baseIndex === -1) return parts.find((part) => !isAddressNumber(part)) ?? '지역 미확인'

  const district = parts[baseIndex]
  const afterBase = parts.slice(baseIndex + 1)
  const dong = afterBase.find(isAdministrativeArea)
  const road = findRoadAddress(afterBase)?.road ?? ''
  const regionParts = [district, dong, road].filter(Boolean)
  if (regionParts.length) return regionParts.join(' ')
  return '지역 미확인'
}

function isAddressNumber(value: string) {
  return /^\d+(?:-\d+)?(?:번지|호)?$/.test(value)
}

function isAdministrativeArea(value: string) {
  return /^(?!\d).+(?:동|읍|면|리)$/.test(value)
}

function displayRegion(customer: Pick<Customer, 'address' | 'region'>) {
  return customer.address.trim() ? extractRegion(customer.address) : customer.region ?? '주소 없음'
}

function birthDateLabel(customer: Pick<Customer, 'birthDate'>) {
  return parseBirthDate(customer.birthDate ?? '') ?? '생년월일 없음'
}

function ageGroup(customer: Pick<Customer, 'birthDate'>) {
  const birthDate = parseBirthDate(customer.birthDate ?? '')
  if (!birthDate) return '나이 미상'
  const age = calculateAge(birthDate)
  if (age < 20) return '10대 이하'
  if (age >= 80) return '80대 이상'
  return `${Math.floor(age / 10) * 10}대`
}

function normalizeAddressForMapSearch(address: string) {
  const normalized = normalizeAddressText(address)
  if (!normalized) return ''

  const parts = normalized.split(' ').filter(Boolean)
  const roadAddress = findRoadAddress(parts)
  if (!roadAddress) return normalized
  const base = [...parts.slice(0, roadAddress.index), roadAddress.road]
  if (roadAddress.buildingNumber) base.push(roadAddress.buildingNumber)
  return base.join(' ')
}

function expandAddressContext(address: string) {
  const normalized = normalizeAddressForMapSearch(address)
  if (/^(수정구|중원구|분당구)\s/.test(normalized)) return `경기도 성남시 ${normalized}`
  return normalized
}

function preferredGeocodeQuery(address: string) {
  return expandAddressContext(address) || normalizeAddressForMapSearch(address)
}

function normalizeAddressForRoadSearch(address: string) {
  const exact = normalizeAddressForMapSearch(address)
  const parts = exact.split(' ').filter(Boolean)
  const roadAddress = findRoadAddress(parts)
  if (!roadAddress) return exact
  return [...parts.slice(0, roadAddress.index), roadAddress.road].join(' ')
}

function normalizeAddressForBroadRoadSearch(address: string) {
  const roadOnly = normalizeAddressForRoadSearch(address)
  const parts = roadOnly.split(' ').filter(Boolean)
  const roadAddress = findRoadAddress(parts)
  if (!roadAddress) return roadOnly
  const broadRoad = roadAddress.road.replace(/\d+(?:번)?길$/, '')
  if (!broadRoad || broadRoad === roadAddress.road) return roadOnly
  return [...parts.slice(0, roadAddress.index), broadRoad].join(' ')
}

function geocodeCandidateQueries(address: string) {
  return uniqueNonEmpty([
    expandAddressContext(address),
    normalizeAddressForMapSearch(address),
    expandAddressContext(normalizeAddressForRoadSearch(address)),
    normalizeAddressForRoadSearch(address),
    expandAddressContext(normalizeAddressForBroadRoadSearch(address)),
    normalizeAddressForBroadRoadSearch(address),
    address,
  ])
}

function sharedGeocodeCandidateQueries(address: string) {
  return uniqueNonEmpty([
    expandAddressContext(address),
    normalizeAddressForMapSearch(address),
    expandAddressContext(normalizeAddressForRoadSearch(address)),
    normalizeAddressForRoadSearch(address),
    expandAddressContext(normalizeAddressForBroadRoadSearch(address)),
    normalizeAddressForBroadRoadSearch(address),
  ])
}

function isSearchableAddress(address: string) {
  const normalized = normalizeAddressText(address)
  if (!normalized || /주소\s*미확인/.test(normalized)) return false
  return Boolean(findRoadAddress(normalized.split(' ').filter(Boolean)))
}

function geocodeGroupKey(customer: Customer) {
  return sharedGeocodeCandidateQueries(customer.address).join('|') || normalizeAddressText(customer.address)
}

function mapMissingReason(customer: Customer) {
  if (!normalizeAddressText(customer.address) || /주소\s*미확인/.test(normalizeAddressText(customer.address))) return '주소 없음'
  if (!isSearchableAddress(customer.address)) return '도로명주소 인식 실패'
  if (needsCoordinateCheck(customer)) return '위치 확인 필요'
  return 'OSM 검색 결과 없음'
}

function needsCoordinateCheck(customer: Customer) {
  if (!isSearchableAddress(customer.address)) return false
  if (customer.coordinateSource !== 'geocoded') return false
  if (!customer.geocodeQuery) return true
  return !geocodeCandidateQueries(customer.address).includes(customer.geocodeQuery)
}

function normalizeAddressText(address: string) {
  return address
    .replace(/\([^)]*\)/g, ' ')
    .split(',')[0]
    .replace(/[，、]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}

function parseRoadAddressToken(value: string) {
  if (isAddressNumber(value)) return null
  const branchRoad = value.match(/^(.+(?:대로|로)\d+(?:번)?길)(\d+(?:-\d+)?)?(?:번지|호)?$/)
  if (branchRoad) return { road: branchRoad[1], buildingNumber: branchRoad[2] ?? '' }
  const standardRoad = value.match(/^(.+?(?:대로|로|길))(\d+(?:-\d+)?)?(?:번지|호)?$/)
  if (standardRoad) return { road: standardRoad[1], buildingNumber: standardRoad[2] ?? '' }
  return null
}

function findRoadAddress(parts: string[]) {
  for (let index = 0; index < parts.length; index += 1) {
    const parsed = parseRoadAddressToken(parts[index])
    if (!parsed) continue

    const next = parts[index + 1] ?? ''
    const nextBranch = next.match(/^(\d+(?:번)?길)(\d+(?:-\d+)?)?(?:번지|호)?$/)
    if (nextBranch && /(?:대로|로)$/.test(parsed.road)) {
      const following = parts[index + 2] ?? ''
      const buildingNumber = nextBranch[2] || (isAddressNumber(following) ? following : '')
      return { index, road: `${parsed.road}${nextBranch[1]}`, buildingNumber }
    }

    if (parsed.buildingNumber) return { index, ...parsed }
    if (next && isAddressNumber(next)) return { index, road: parsed.road, buildingNumber: next }
    return { index, ...parsed }
  }
  return null
}

function parseBirthDate(value: string) {
  const trimmed = value.trim()
  if (!trimmed) return ''
  const digits = trimmed.replace(/\D/g, '')
  let year = ''
  let month = ''
  let day = ''
  if (digits.length >= 8) {
    year = digits.slice(0, 4)
    month = digits.slice(4, 6)
    day = digits.slice(6, 8)
  } else if (digits.length === 6) {
    const yy = Number(digits.slice(0, 2))
    const currentYY = new Date().getFullYear() % 100
    year = `${yy > currentYY ? 1900 + yy : 2000 + yy}`
    month = digits.slice(2, 4)
    day = digits.slice(4, 6)
  } else if (digits.length === 4) {
    year = digits
    month = '01'
    day = '01'
  } else {
    return ''
  }
  const iso = `${year}-${month}-${day}`
  const parsed = new Date(`${iso}T00:00:00`)
  if (Number.isNaN(parsed.getTime())) return ''
  if (parsed.getFullYear() !== Number(year) || parsed.getMonth() + 1 !== Number(month) || parsed.getDate() !== Number(day)) return ''
  return iso
}

function calculateAge(birthDate: string) {
  const [year, month, day] = birthDate.split('-').map(Number)
  const now = new Date()
  let age = now.getFullYear() - year
  if (now.getMonth() + 1 < month || (now.getMonth() + 1 === month && now.getDate() < day)) age -= 1
  return age
}

function customerMatchesSearch(customer: Customer, query: string) {
  const normalized = normalizeSearchText(query)
  if (!normalized) return true
  const phoneQuery = cleanPhone(query).replace(/\D/g, '')
  const phoneTarget = cleanPhone(customer.phoneNumber).replace(/\D/g, '')
  return [customer.name, customer.phoneNumber, customer.address]
    .some((value) => normalizeSearchText(value).includes(normalized))
    || Boolean(phoneQuery && phoneTarget.includes(phoneQuery))
}

function normalizeSearchText(value: string) {
  return value.trim().toLocaleLowerCase('ko-KR').replace(/\s+/g, '')
}

function uniqueNonEmpty(values: string[]) {
  return Array.from(new Set(values.map((value) => value.trim()).filter(Boolean)))
}

function mergeBackupPayloads(remote: AppBackupPayload, local: AppBackupPayload): AppBackupPayload {
  return {
    schemaVersion: 1,
    exportedAt: new Date().toISOString(),
    customerLists: mergeById(remote.customerLists, local.customerLists),
    customers: mergeById(remote.customers, local.customers),
    visitLogs: mergeById(remote.visitLogs, local.visitLogs),
    contactLogs: mergeById(remote.contactLogs, local.contactLogs),
    visitSchedules: mergeById(remote.visitSchedules, local.visitSchedules),
    visitScheduleItems: mergeById(remote.visitScheduleItems, local.visitScheduleItems),
    messageTemplates: mergeById(remote.messageTemplates, local.messageTemplates),
  }
}

function mergeById<T extends { id: string }>(remoteItems: T[] = [], localItems: T[] = []) {
  const merged = new Map<string, T>()
  remoteItems.forEach((item) => merged.set(item.id, item))
  localItems.forEach((item) => {
    const previous = merged.get(item.id)
    if (!previous || itemTimestamp(item) >= itemTimestamp(previous)) {
      merged.set(item.id, item)
    }
  })
  return Array.from(merged.values())
}

function itemTimestamp(item: Record<string, unknown>) {
  const value = item.updatedAt ?? item.createdAt ?? item.importedAt ?? item.visitedAt ?? item.completedAt ?? ''
  const time = new Date(String(value)).getTime()
  return Number.isFinite(time) ? time : 0
}

function loadGoogleDriveAccount(): GoogleDriveAccount | null {
  try {
    const raw = localStorage.getItem(googleDriveAccountKey)
    return raw ? JSON.parse(raw) as GoogleDriveAccount : null
  } catch {
    localStorage.removeItem(googleDriveAccountKey)
    return null
  }
}

function loadDisplayMode(): DisplayMode {
  return localStorage.getItem(displayModeKey) === 'list' ? 'list' : 'cards'
}

function distanceKm(from: [number, number], to: [number, number]) {
  const radius = 6371
  const dLat = ((to[0] - from[0]) * Math.PI) / 180
  const dLon = ((to[1] - from[1]) * Math.PI) / 180
  const lat1 = (from[0] * Math.PI) / 180
  const lat2 = (to[0] * Math.PI) / 180
  const a = Math.sin(dLat / 2) ** 2 + Math.sin(dLon / 2) ** 2 * Math.cos(lat1) * Math.cos(lat2)
  return radius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

function formatTime(value: string) {
  return new Intl.DateTimeFormat('ko-KR', {
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value))
}

function blankCustomerForm(): CustomerForm {
  return { name: '', phoneNumber: '', address: '', birthDate: '', notes: '' }
}

function customerToForm(customer: Customer): CustomerForm {
  return {
    name: customer.name,
    phoneNumber: customer.phoneNumber,
    address: customer.address,
    birthDate: customer.birthDate ?? '',
    notes: customer.notes,
  }
}

function isPwaStandalone() {
  const navigatorWithStandalone = window.navigator as Navigator & { standalone?: boolean }
  return window.matchMedia('(display-mode: standalone)').matches || Boolean(navigatorWithStandalone.standalone)
}

function isIosDevice() {
  return /iPhone|iPad|iPod/i.test(window.navigator.userAgent)
}

function wait(ms: number) {
  return new Promise((resolve) => window.setTimeout(resolve, ms))
}

async function fetchGeocodeResult(query: string) {
  const url = new URL('https://nominatim.openstreetmap.org/search')
  url.searchParams.set('format', 'jsonv2')
  url.searchParams.set('q', query)
  url.searchParams.set('countrycodes', 'kr')
  url.searchParams.set('limit', '1')
  url.searchParams.set('accept-language', 'ko')

  const response = await fetch(url.toString(), {
    headers: { Accept: 'application/json' },
  })
  if (!response.ok) throw new Error('geocode failed')
  const results = await response.json() as Array<{ lat: string; lon: string }>
  const best = results[0]
  if (!best) return null
  const latitude = Number(best.lat)
  const longitude = Number(best.lon)
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null
  return { latitude, longitude }
}

async function geocodeAddress(address: string) {
  const candidates = geocodeCandidateQueries(address)
  for (const query of candidates) {
    const result = await fetchGeocodeResult(query)
    if (result) return { ...result, query }
  }
  return null
}

function App() {
  const [tab, setTab] = useState<TabKey>('today')
  const [todayMode, setTodayMode] = useState<TodayMode>('schedule')
  const [listFilter, setListFilter] = useState<ListFilterKey>('open')
  const [activeListId, setActiveListId] = useState<string>(() => localStorage.getItem('activeListId') ?? '')
  const [selectedCustomerId, setSelectedCustomerId] = useState<string>('')
  const [customerLists, setCustomerLists] = useState<CustomerList[]>([])
  const [customers, setCustomers] = useState<Customer[]>([])
  const [visitLogs, setVisitLogs] = useState<VisitLog[]>([])
  const [contactLogs, setContactLogs] = useState<ContactLog[]>([])
  const [schedules, setSchedules] = useState<VisitSchedule[]>([])
  const [scheduleItems, setScheduleItems] = useState<VisitScheduleItem[]>([])
  const [templates, setTemplates] = useState<MessageTemplate[]>([])
  const [location, setLocation] = useState<[number, number]>(defaultCenter)
  const [hasUserLocation, setHasUserLocation] = useState(false)
  const [toast, setToast] = useState('')
  const [csv, setCsv] = useState<ParsedCsv | null>(null)
  const [importCompany, setImportCompany] = useState('')
  const [importListName, setImportListName] = useState('')
  const [importSourceFile, setImportSourceFile] = useState('')
  const [newTemplateTitle, setNewTemplateTitle] = useState('')
  const [newTemplateBody, setNewTemplateBody] = useState('')
  const [editingTemplateId, setEditingTemplateId] = useState<string | null>(null)
  const [editingTemplateTitle, setEditingTemplateTitle] = useState('')
  const [editingTemplateBody, setEditingTemplateBody] = useState('')
  const [messageCustomerId, setMessageCustomerId] = useState<string | null>(null)
  const [mapFocusTick, setMapFocusTick] = useState(0)
  const [lastBackupAt, setLastBackupAt] = useState<string>(() => localStorage.getItem('lastBackupAt') ?? '')
  const [lastDriveSyncAt, setLastDriveSyncAt] = useState<string>(() => localStorage.getItem(lastDriveSyncAtKey) ?? '')
  const [lastLocalChangeAt, setLastLocalChangeAt] = useState<string>(() => localStorage.getItem(lastLocalChangeAtKey) ?? '')
  const [driveSyncBusy, setDriveSyncBusy] = useState(false)
  const [googleDriveAccount, setGoogleDriveAccount] = useState<GoogleDriveAccount | null>(() => loadGoogleDriveAccount())
  const [isStandalone, setIsStandalone] = useState(() => isPwaStandalone())
  const [installPrompt, setInstallPrompt] = useState<BeforeInstallPromptEvent | null>(null)
  const [showInstallGuide, setShowInstallGuide] = useState(false)
  const [geocodeProgress, setGeocodeProgress] = useState<GeocodeProgress>({ running: false, done: 0, total: 0, failed: 0, current: '' })
  const [editingCustomerId, setEditingCustomerId] = useState<string | 'new' | null>(null)
  const [customerForm, setCustomerForm] = useState<CustomerForm>(() => blankCustomerForm())
  const [historyCustomerId, setHistoryCustomerId] = useState<string | null>(null)
  const [noteCustomerId, setNoteCustomerId] = useState<string | null>(null)
  const [noteText, setNoteText] = useState('')
  const [customerSearch, setCustomerSearch] = useState('')
  const [displayMode, setDisplayMode] = useState<DisplayMode>(() => loadDisplayMode())
  const [metricSheet, setMetricSheet] = useState<MetricSheet | null>(null)
  const backupInputRef = useRef<HTMLInputElement | null>(null)
  const autoLocationPreparedRef = useRef<Set<string>>(new Set())
  const geocodeActiveListRef = useRef<((options?: { automatic?: boolean }) => Promise<void>) | null>(null)

  const activeList = customerLists.find((list) => list.id === activeListId) ?? customerLists[0]
  const activeCustomers = useMemo(() => customers.filter((customer) => customer.customerListId === activeList?.id), [customers, activeList])
  const activeVisits = useMemo(() => visitLogs.filter((log) => log.customerListId === activeList?.id), [visitLogs, activeList])
  const activeSchedule = schedules.find((schedule) => schedule.customerListId === activeList?.id && schedule.date === todayKey())
  const activeScheduleItems = scheduleItems
    .filter((item) => item.customerListId === activeList?.id && item.scheduleId === activeSchedule?.id)
    .sort((a, b) => a.orderIndex - b.orderIndex)

  const openCustomers = activeCustomers.filter((customer) => customer.status === 'open')
  const completedTodayIds = new Set(
    activeVisits
      .filter((log) => log.visitedAt.slice(0, 10) === todayKey())
      .map((log) => log.customerId),
  )
  const remainingCustomers = openCustomers.filter((customer) => !completedTodayIds.has(customer.id))

  const nearestCustomers = [...remainingCustomers].sort((a, b) => {
    const aDistance = customerDistance(a)
    const bDistance = customerDistance(b)
    return aDistance - bDistance
  })

  const pendingScheduleCustomers = activeScheduleItems
    .filter((item) => item.status === 'pending' && !completedTodayIds.has(item.customerId))
    .map((item) => activeCustomers.find((customer) => customer.id === item.customerId))
    .filter(Boolean) as Customer[]

  const currentCustomer = todayMode === 'schedule' ? pendingScheduleCustomers[0] : nearestCustomers[0]
  const selectedCustomer = activeCustomers.find((customer) => customer.id === selectedCustomerId) ?? currentCustomer ?? nearestCustomers[0]
  const historyCustomer = customers.find((customer) => customer.id === historyCustomerId) ?? null
  const noteCustomer = customers.find((customer) => customer.id === noteCustomerId) ?? null
  const touchedCustomers = activeCustomers.filter((customer) => customerHistory(customer).length > 0)
  const doneCustomers = activeCustomers.filter((customer) => customer.status === 'done')
  const searchedCustomers = activeCustomers.filter((customer) => customerMatchesSearch(customer, customerSearch))
  const geocodableCustomers = activeCustomers.filter(needsMapLocationRefresh)
  const geocodableSignature = geocodableCustomers.map((customer) => `${customer.id}:${customer.updatedAt}`).join('|')
  const trustedCoordinateCount = activeCustomers.filter(hasTrustedCoordinates).length
  const hasUnsyncedChanges = Boolean(lastLocalChangeAt && (!lastDriveSyncAt || lastLocalChangeAt > lastDriveSyncAt))

  function changeDisplayMode(mode: DisplayMode) {
    localStorage.setItem(displayModeKey, mode)
    setDisplayMode(mode)
  }

  function markLocalDataChanged() {
    const now = new Date().toISOString()
    localStorage.setItem(lastLocalChangeAtKey, now)
    setLastLocalChangeAt(now)
  }

  useEffect(() => {
    async function seedAndLoadInitialData() {
      const count = await appDb.customerLists.count()
      if (count === 0) {
        await appDb.transaction('rw', [appDb.customerLists, appDb.customers, appDb.visitSchedules, appDb.visitScheduleItems, appDb.visitLogs, appDb.messageTemplates], async () => {
          await appDb.customerLists.bulkPut(sampleLists)
          await appDb.customers.bulkPut(sampleCustomers)
          await appDb.visitSchedules.bulkPut(sampleSchedules)
          if (sampleScheduleItems.length) await appDb.visitScheduleItems.bulkPut(sampleScheduleItems)
          await appDb.visitLogs.bulkPut(sampleVisitLogs)
          await appDb.messageTemplates.bulkPut(defaultTemplates)
        })
      } else {
        await Promise.all(['si-1', 'si-2', 'si-3', 'si-4', 'si-5'].map((id) => appDb.visitScheduleItems.delete(id)))
        await appDb.customers.toCollection().modify((customer) => {
          const entry = customer as unknown as { coordinateSource?: string; latitude?: number; longitude?: number }
          if (entry.coordinateSource === 'estimated') {
            delete entry.latitude
            delete entry.longitude
            delete entry.coordinateSource
          }
        })
      }
      await appDb.customers.toCollection().modify((customer) => {
        const nextRegion = customer.address.trim() ? extractRegion(customer.address) : '주소 없음'
        if (customer.region !== nextRegion) {
          customer.region = nextRegion
        }
      })
      const [nextLists, nextCustomers, nextVisits, nextContacts, nextSchedules, nextScheduleItems, nextTemplates] = await Promise.all([
        appDb.customerLists.orderBy('importedAt').reverse().toArray(),
        appDb.customers.toArray(),
        appDb.visitLogs.orderBy('visitedAt').reverse().toArray(),
        appDb.contactLogs.orderBy('createdAt').reverse().toArray(),
        appDb.visitSchedules.toArray(),
        appDb.visitScheduleItems.toArray(),
        appDb.messageTemplates.toArray(),
      ])
      setCustomerLists(nextLists)
      setCustomers(nextCustomers)
      setVisitLogs(nextVisits)
      setContactLogs(nextContacts)
      setSchedules(nextSchedules)
      setScheduleItems(nextScheduleItems)
      setTemplates(nextTemplates)
      setActiveListId((current) => current || nextLists[0]?.id || '')
    }
    void seedAndLoadInitialData()
  }, [])

  useEffect(() => {
    async function requestPersistentStorage() {
      if ('storage' in navigator && 'persist' in navigator.storage) {
        try {
          await navigator.storage.persist()
        } catch {
          // Persistent storage is best-effort; the app still works without it.
        }
      }
    }
    void requestPersistentStorage()
  }, [])

  useEffect(() => {
    const displayMode = window.matchMedia('(display-mode: standalone)')
    const legacyDisplayMode = displayMode as MediaQueryList & {
      addListener?: (listener: () => void) => void
      removeListener?: (listener: () => void) => void
    }
    const syncStandalone = () => setIsStandalone(isPwaStandalone())
    const shouldShowGuide = () => !isPwaStandalone() && localStorage.getItem(installGuideDismissedKey) !== 'true'

    const handleBeforeInstallPrompt = (event: Event) => {
      event.preventDefault()
      setInstallPrompt(event as BeforeInstallPromptEvent)
      if (shouldShowGuide()) setShowInstallGuide(true)
    }

    window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt)
    window.addEventListener('appinstalled', syncStandalone)
    if (typeof displayMode.addEventListener === 'function') {
      displayMode.addEventListener('change', syncStandalone)
    } else {
      legacyDisplayMode.addListener?.(syncStandalone)
    }

    const timer = window.setTimeout(() => {
      syncStandalone()
      if (shouldShowGuide()) setShowInstallGuide(true)
    }, 900)

    return () => {
      window.clearTimeout(timer)
      window.removeEventListener('beforeinstallprompt', handleBeforeInstallPrompt)
      window.removeEventListener('appinstalled', syncStandalone)
      if (typeof displayMode.removeEventListener === 'function') {
        displayMode.removeEventListener('change', syncStandalone)
      } else {
        legacyDisplayMode.removeListener?.(syncStandalone)
      }
    }
  }, [])

  useEffect(() => {
    if (!toast) return
    const timer = window.setTimeout(() => setToast(''), 3000)
    return () => window.clearTimeout(timer)
  }, [toast])

  useEffect(() => {
    if (activeListId) {
      localStorage.setItem('activeListId', activeListId)
    } else {
      localStorage.removeItem('activeListId')
    }
  }, [activeListId])

  useEffect(() => {
    if (!customerLists.length || lastBackupAt) return
    showToast('아직 백업 기록이 없습니다. 설정에서 JSON 백업을 내보내세요')
  }, [customerLists.length, lastBackupAt])

  useEffect(() => {
    if (!lastBackupAt) return
    const daysSinceBackup = (Date.now() - new Date(lastBackupAt).getTime()) / (1000 * 60 * 60 * 24)
    if (daysSinceBackup >= 7) {
      showToast('마지막 백업 후 7일이 지났습니다. JSON 백업을 권장합니다')
    }
  }, [lastBackupAt])

  useEffect(() => {
    if (tab !== 'today' || todayMode !== 'map' || !activeList || !geocodableSignature || geocodeProgress.running) return
    const autoKey = `${activeList.id}:${geocodableSignature}`
    if (autoLocationPreparedRef.current.has(autoKey)) return
    autoLocationPreparedRef.current.add(autoKey)
    const timer = window.setTimeout(() => {
      void geocodeActiveListRef.current?.({ automatic: true })
    }, 600)
    return () => window.clearTimeout(timer)
  }, [activeList, geocodableSignature, geocodeProgress.running, tab, todayMode])

  async function refresh() {
    const [nextLists, nextCustomers, nextVisits, nextContacts, nextSchedules, nextScheduleItems, nextTemplates] = await Promise.all([
      appDb.customerLists.orderBy('importedAt').reverse().toArray(),
      appDb.customers.toArray(),
      appDb.visitLogs.orderBy('visitedAt').reverse().toArray(),
      appDb.contactLogs.orderBy('createdAt').reverse().toArray(),
      appDb.visitSchedules.toArray(),
      appDb.visitScheduleItems.toArray(),
      appDb.messageTemplates.toArray(),
    ])
    setCustomerLists(nextLists)
    setCustomers(nextCustomers)
    setVisitLogs(nextVisits)
    setContactLogs(nextContacts)
    setSchedules(nextSchedules)
    setScheduleItems(nextScheduleItems)
    setTemplates(nextTemplates)
    if (!activeListId && nextLists[0]) {
      setActiveListId(nextLists[0].id)
    } else if (activeListId && !nextLists.some((list) => list.id === activeListId)) {
      setActiveListId(nextLists[0]?.id ?? '')
    }
  }

  function customerDistance(customer: Customer) {
    if (!hasTrustedCoordinates(customer)) return Number.MAX_SAFE_INTEGER
    return distanceKm(location, [customer.latitude, customer.longitude])
  }

  function customerDistanceLabel(customer: Customer) {
    if (!hasTrustedCoordinates(customer)) return '거리 미확인'
    return `약 ${customerDistance(customer).toFixed(1)}km`
  }

  function showToast(message: string) {
    setToast(message)
  }

  async function addTouchLog(customer: Customer, type: ContactLog['type'], result: ContactLog['result'], messageBody = '', templateId?: string) {
    await appDb.contactLogs.add({
      id: makeId('contact'),
      customerListId: customer.customerListId,
      customerId: customer.id,
      type,
      templateId,
      messageBody,
      result,
      createdAt: new Date().toISOString(),
    })
    markLocalDataChanged()
  }

  function requestLocation() {
    if (!navigator.geolocation) {
      showToast('이 브라우저에서 위치 기능을 사용할 수 없습니다')
      return
    }
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setLocation([position.coords.latitude, position.coords.longitude])
        setHasUserLocation(true)
        setMapFocusTick((value) => value + 1)
        showToast('현재 위치를 반영했습니다')
      },
      () => showToast('위치 권한을 허용해야 가까운 순 정렬이 정확해집니다'),
      { enableHighAccuracy: true, timeout: 8000 },
    )
  }

  async function completeVisit(customer: Customer) {
    const now = new Date().toISOString()
    const item = activeScheduleItems.find((scheduleItem) => scheduleItem.customerId === customer.id && scheduleItem.status === 'pending')
    await appDb.transaction('rw', appDb.customers, appDb.contactLogs, appDb.visitScheduleItems, async () => {
      await appDb.customers.update(customer.id, { status: 'done', updatedAt: now })
      await appDb.contactLogs.add({
        id: makeId('contact'),
        customerListId: customer.customerListId,
        customerId: customer.id,
        type: 'statusComplete',
        messageBody: '고객 서비스 완료 처리',
        result: 'completed',
        createdAt: now,
      })
      if (item) {
        await appDb.visitScheduleItems.update(item.id, { status: 'completed', completedAt: now })
      }
    })
    markLocalDataChanged()
    await refresh()
    showToast(`${customer.name} 완료 처리가 저장되었습니다`)
  }

  async function reopenCustomer(customer: Customer) {
    const now = new Date().toISOString()
    const completedItems = activeScheduleItems.filter((scheduleItem) => scheduleItem.customerId === customer.id && scheduleItem.status === 'completed')
    await appDb.transaction('rw', appDb.customers, appDb.contactLogs, appDb.visitScheduleItems, async () => {
      await appDb.customers.update(customer.id, { status: 'open', updatedAt: now })
      await appDb.contactLogs.add({
        id: makeId('contact'),
        customerListId: customer.customerListId,
        customerId: customer.id,
        type: 'statusReopen',
        messageBody: '완료 상태 취소',
        result: 'reopened',
        createdAt: now,
      })
      await Promise.all(completedItems.map((item) => appDb.visitScheduleItems.update(item.id, { status: 'pending', completedAt: undefined })))
    })
    markLocalDataChanged()
    await refresh()
    showToast(`${customer.name} 고객을 다시 활성화했습니다`)
  }

  function sendManualSms(customer: Customer) {
    const phone = cleanPhone(customer.phoneNumber)
    if (!hasDialablePhone(customer.phoneNumber)) {
      showToast('연락처가 없어 문자앱을 열 수 없습니다. 고객 수정에서 연락처를 확인하세요')
      return
    }
    void addTouchLog(customer, 'manualSms', 'opened').then(refresh)
    window.location.href = `sms:${phone}`
  }

  function sendTemplateSms(customer: Customer, template: MessageTemplate) {
    const phone = cleanPhone(customer.phoneNumber)
    if (!hasDialablePhone(customer.phoneNumber)) {
      showToast('연락처가 없어 문자앱을 열 수 없습니다. 고객 수정에서 연락처를 확인하세요')
      return
    }
    const body = fillTemplate(template.body, customer)
    if (navigator.clipboard?.writeText) {
      void navigator.clipboard.writeText(body)
        .then(() => showToast('템플릿 문자를 복사했습니다. 문자 앱에서 붙여넣어 전송하세요'))
        .catch(() => showToast('본문 복사가 제한되었습니다. 템플릿 내용을 직접 복사하세요'))
    } else {
      showToast('본문 복사가 제한되었습니다. 템플릿 내용을 직접 복사하세요')
    }
    void addTouchLog(customer, 'templateSms', 'sentByUser', body, template.id).then(refresh)
    window.location.href = `sms:${phone}`
  }

  function callCustomer(customer: Customer) {
    const phone = cleanPhone(customer.phoneNumber)
    if (!hasDialablePhone(customer.phoneNumber)) {
      showToast('연락처가 없어 전화앱을 열 수 없습니다. 고객 수정에서 연락처를 확인하세요')
      return
    }
    void addTouchLog(customer, 'call', 'opened').then(refresh)
    window.location.href = `tel:${phone}`
  }

  function navigateCustomer(customer: Customer) {
    if (!customer.address.trim() && !customer.name.trim()) {
      showToast('길찾기에 사용할 주소가 없습니다')
      return
    }
    if (hasTrustedCoordinates(customer)) {
      openTmapRoute(customer)
      return
    }
    openTmapSearch(customer)
  }

  function hasTrustedCoordinates(customer: Customer): customer is Customer & { latitude: number; longitude: number } {
    return Boolean(
      typeof customer.latitude === 'number' &&
      typeof customer.longitude === 'number' &&
      (customer.coordinateSource === 'csv' || customer.coordinateSource === 'sample' || customer.coordinateSource === 'geocoded'),
    )
  }

  function needsMapLocationRefresh(customer: Customer) {
    if (!isSearchableAddress(customer.address)) return false
    if (!hasTrustedCoordinates(customer)) return true
    if (customer.coordinateSource !== 'geocoded') return false
    return needsCoordinateCheck(customer)
  }

  function openTmapRoute(customer: Customer) {
    const goalName = encodeURIComponent(navigationDestination(customer))
    const goalX = customer.longitude
    const goalY = customer.latitude
    const tmapUrl = `tmap://route?goalx=${goalX}&goaly=${goalY}&goalname=${goalName}`
    openExternalApp(tmapUrl)
  }

  function openTmapSearch(customer: Customer) {
    const destination = navigationDestination(customer)
    const encodedDestination = encodeURIComponent(destination)
    const tmapUrl = `tmap://?search=${encodedDestination}`
    showToast('정확한 좌표가 없어 티맵에서 주소를 검색합니다')
    openExternalApp(tmapUrl)
  }

  function navigationDestination(customer: Customer) {
    return preferredGeocodeQuery(customer.address) || customer.address.trim() || customer.name.trim()
  }

  function openExternalApp(url: string) {
    window.location.href = url
  }

  function fillTemplate(templateBody: string, customer: Customer) {
    return templateBody
      .replaceAll('{고객명}', customer.name)
      .replaceAll('{고객사명}', activeList?.companyName ?? '')
      .replaceAll('{지역}', displayRegion(customer))
      .replaceAll('{주소}', customer.address)
  }

  function handleCsvFile(file: File) {
    setImportSourceFile(file.name)
    Papa.parse<string[]>(file, {
      skipEmptyLines: true,
      complete: (result) => {
        const rows = result.data.filter((row) => row.some((cell) => String(cell).trim()))
        const headers = rows[0]?.map((value) => String(value).trim()) ?? []
        setCsv({ headers, rows: rows.slice(1), mapping: detectMapping(headers) })
        showToast('CSV 헤더를 자동 인식했습니다')
      },
    })
  }

  async function saveImportedList() {
    if (!csv) {
      showToast('CSV 파일을 먼저 선택하세요')
      return
    }
    if (csv.mapping.name === null) {
      showToast('고객명 열은 필수입니다')
      return
    }
    if (csv.mapping.phoneNumber === null && csv.mapping.address === null) {
      showToast('전화번호 또는 주소 열 중 하나는 필요합니다')
      return
    }
    if (!importCompany.trim() || !importListName.trim()) {
      showToast('고객사 이름과 고객리스트 이름을 입력하세요')
      return
    }
    const now = new Date().toISOString()
    const listId = makeId('list')
    const list: CustomerList = {
      id: listId,
      name: importListName.trim(),
      companyName: importCompany.trim(),
      sourceFileName: importSourceFile || 'import.csv',
      importedAt: now,
      createdAt: now,
      updatedAt: now,
    }
    const nextCustomers = csv.rows
      .map((row): Customer | null => {
        const name = getMappedValue(row, csv.mapping.name)
        const phoneNumber = getMappedValue(row, csv.mapping.phoneNumber)
        const address = getMappedValue(row, csv.mapping.address)
        const birthDate = parseBirthDate(getMappedValue(row, csv.mapping.birthDate))
        const notes = getMappedValue(row, csv.mapping.notes)
        if (!name || (!phoneNumber && !address)) return null
        const mappedLatitude = parseCoordinate(getMappedValue(row, csv.mapping.latitude), 'latitude')
        const mappedLongitude = parseCoordinate(getMappedValue(row, csv.mapping.longitude), 'longitude')
        const hasCsvCoordinates = mappedLatitude !== undefined && mappedLongitude !== undefined
        return {
          id: makeId('customer'),
          customerListId: listId,
          name,
          phoneNumber,
          address,
          birthDate: birthDate || undefined,
          notes,
          latitude: hasCsvCoordinates ? mappedLatitude : undefined,
          longitude: hasCsvCoordinates ? mappedLongitude : undefined,
          coordinateSource: hasCsvCoordinates ? 'csv' : undefined,
          region: address ? extractRegion(address) : '주소 없음',
          status: 'open',
          createdAt: now,
          updatedAt: now,
        }
      })
      .filter(Boolean) as Customer[]
    const schedule: VisitSchedule = {
      id: makeId('schedule'),
      customerListId: listId,
      date: todayKey(),
      title: `${list.name} 오늘 스케줄`,
      createdAt: now,
      updatedAt: now,
    }
    await appDb.transaction('rw', appDb.customerLists, appDb.customers, appDb.visitSchedules, appDb.visitScheduleItems, async () => {
      await appDb.customerLists.add(list)
      await appDb.customers.bulkAdd(nextCustomers)
      await appDb.visitSchedules.add(schedule)
    })
    setActiveListId(listId)
    setTab('customers')
    setCsv(null)
    setImportCompany('')
    setImportListName('')
    setImportSourceFile('')
    markLocalDataChanged()
    await refresh()
    showToast(`${nextCustomers.length}명 저장 완료`)
  }

  function getMappedValue(row: string[], index: number | null) {
    if (index === null) return ''
    return String(row[index] ?? '').trim()
  }

  async function addSelectedToSchedule(customer: Customer) {
    if (!activeSchedule) return
    const maxOrder = activeScheduleItems.reduce((max, item) => Math.max(max, item.orderIndex), 0)
    const existing = activeScheduleItems.find((item) => item.customerId === customer.id)
    if (existing) {
      showToast('이미 오늘 스케줄에 포함된 고객입니다')
      return
    }
    await appDb.visitScheduleItems.add({
      id: makeId('schedule-item'),
      scheduleId: activeSchedule.id,
      customerListId: customer.customerListId,
      customerId: customer.id,
      orderIndex: maxOrder + 1,
      status: 'pending',
    })
    markLocalDataChanged()
    await refresh()
    showToast(`${customer.name} 고객을 오늘 스케줄에 추가했습니다`)
  }

  async function removeScheduleItem(item: VisitScheduleItem, customer?: Customer) {
    const remainingItems = activeScheduleItems.filter((entry) => entry.id !== item.id)
    await appDb.transaction('rw', appDb.visitScheduleItems, async () => {
      await appDb.visitScheduleItems.delete(item.id)
      await Promise.all(remainingItems.map((entry, index) => appDb.visitScheduleItems.update(entry.id, { orderIndex: index + 1 })))
    })
    markLocalDataChanged()
    await refresh()
    showToast(`${customer?.name ?? '고객'}을 오늘 스케줄에서 삭제했습니다`)
  }

  async function geocodeActiveList(options: { automatic?: boolean } = {}) {
    if (geocodeProgress.running) return
    const targets = activeCustomers.filter(needsMapLocationRefresh)
    if (!targets.length) {
      if (!options.automatic) showToast('지도에 표시할 위치가 모두 준비되어 있습니다')
      return
    }
    const targetGroups = Array.from(
      targets.reduce<Map<string, Customer[]>>((groups, customer) => {
        const key = geocodeGroupKey(customer)
        groups.set(key, [...(groups.get(key) ?? []), customer])
        return groups
      }, new Map()).values(),
    )

    let failed = 0
    setGeocodeProgress({ running: true, done: 0, total: targetGroups.length, failed: 0, current: '' })
    if (options.automatic) showToast('고객 주소를 지도에 표시하는 중입니다')

    for (let index = 0; index < targetGroups.length; index += 1) {
      const group = targetGroups[index]
      const representative = group[0]
      const currentLabel = group.length > 1 ? `${representative.name} 외 ${group.length - 1}명` : representative.name
      setGeocodeProgress({ running: true, done: index, total: targetGroups.length, failed, current: currentLabel })
      try {
        const result = await geocodeAddress(representative.address)
        if (result) {
          const now = new Date().toISOString()
          await Promise.all(group.map((customer) => appDb.customers.update(customer.id, {
              latitude: result.latitude,
              longitude: result.longitude,
              coordinateSource: 'geocoded',
              geocodedAt: now,
              geocodeQuery: result.query,
              updatedAt: now,
            })))
        } else {
          await Promise.all(group
            .filter((customer) => customer.coordinateSource === 'geocoded')
            .map((customer) => appDb.customers.update(customer.id, {
                latitude: undefined,
                longitude: undefined,
                coordinateSource: undefined,
                geocodedAt: undefined,
                geocodeQuery: undefined,
                updatedAt: new Date().toISOString(),
              })))
          failed += group.length
        }
      } catch {
        failed += group.length
      }
      setGeocodeProgress({ running: true, done: index + 1, total: targetGroups.length, failed, current: currentLabel })
      if (index < targetGroups.length - 1) await wait(1100)
    }

    markLocalDataChanged()
    await refresh()
    setGeocodeProgress({ running: false, done: targetGroups.length, total: targetGroups.length, failed, current: '' })
    showToast(failed ? `지도 표시 준비 완료: ${targets.length - failed}명 성공, ${failed}명 확인 필요` : `${targets.length}명 위치를 지도에 표시할 수 있습니다`)
  }

  geocodeActiveListRef.current = geocodeActiveList

  async function sortScheduleByDistance() {
    const sorted = activeScheduleItems
      .map((item) => ({ item, customer: activeCustomers.find((customer) => customer.id === item.customerId) }))
      .filter((entry): entry is { item: VisitScheduleItem; customer: Customer } => Boolean(entry.customer))
      .sort((a, b) => customerDistance(a.customer) - customerDistance(b.customer))
    await Promise.all(sorted.map((entry, index) => appDb.visitScheduleItems.update(entry.item.id, { orderIndex: index + 1 })))
    markLocalDataChanged()
    await refresh()
    showToast('오늘 스케줄을 가까운 순으로 정렬했습니다')
  }

  async function addTemplate() {
    if (!newTemplateTitle.trim() || !newTemplateBody.trim()) {
      showToast('템플릿 제목과 내용을 입력하세요')
      return
    }
    const now = new Date().toISOString()
    await appDb.messageTemplates.add({
      id: makeId('template'),
      title: newTemplateTitle,
      body: newTemplateBody,
      isDefault: false,
      createdAt: now,
      updatedAt: now,
    })
    setNewTemplateTitle('')
    setNewTemplateBody('')
    markLocalDataChanged()
    await refresh()
    showToast('문자 템플릿을 추가했습니다')
  }

  function openTemplateEditor(template: MessageTemplate) {
    setEditingTemplateId(template.id)
    setEditingTemplateTitle(template.title)
    setEditingTemplateBody(template.body)
  }

  function closeTemplateEditor() {
    setEditingTemplateId(null)
    setEditingTemplateTitle('')
    setEditingTemplateBody('')
  }

  async function saveTemplateEdit() {
    if (!editingTemplateId) return
    const title = editingTemplateTitle.trim()
    const body = editingTemplateBody.trim()
    if (!title || !body) {
      showToast('템플릿 제목과 내용을 입력하세요')
      return
    }
    await appDb.messageTemplates.update(editingTemplateId, {
      title,
      body,
      updatedAt: new Date().toISOString(),
    })
    closeTemplateEditor()
    markLocalDataChanged()
    await refresh()
    showToast('문자 템플릿을 수정했습니다')
  }

  async function deleteTemplate(template: MessageTemplate) {
    await appDb.messageTemplates.delete(template.id)
    if (editingTemplateId === template.id) closeTemplateEditor()
    markLocalDataChanged()
    await refresh()
    showToast(`${template.title} 템플릿을 삭제했습니다`)
  }

  async function buildBackupPayload(): Promise<AppBackupPayload> {
    return {
      schemaVersion: 1,
      exportedAt: new Date().toISOString(),
      customerLists: await appDb.customerLists.toArray(),
      customers: await appDb.customers.toArray(),
      visitLogs: await appDb.visitLogs.toArray(),
      contactLogs: await appDb.contactLogs.toArray(),
      visitSchedules: await appDb.visitSchedules.toArray(),
      visitScheduleItems: await appDb.visitScheduleItems.toArray(),
      messageTemplates: await appDb.messageTemplates.toArray(),
    }
  }

  async function exportBackup() {
    const payload = await buildBackupPayload()
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = `outbound-sales-backup-${todayKey()}.json`
    anchor.click()
    URL.revokeObjectURL(url)
    const now = new Date().toISOString()
    localStorage.setItem('lastBackupAt', now)
    setLastBackupAt(now)
    showToast('백업 파일을 내보냈습니다')
  }

  async function importBackup(file: File) {
    const payload = JSON.parse(await file.text())
    await restoreBackupPayload(payload, { markChanged: true })
    showToast('백업을 복원했습니다')
  }

  async function restoreBackupPayload(payload: AppBackupPayload, options: { markChanged?: boolean } = {}) {
    await appDb.transaction('rw', [appDb.customerLists, appDb.customers, appDb.visitLogs, appDb.contactLogs, appDb.visitSchedules, appDb.visitScheduleItems, appDb.messageTemplates], async () => {
      await Promise.all([
        appDb.customerLists.clear(),
        appDb.customers.clear(),
        appDb.visitLogs.clear(),
        appDb.contactLogs.clear(),
        appDb.visitSchedules.clear(),
        appDb.visitScheduleItems.clear(),
        appDb.messageTemplates.clear(),
      ])
      await appDb.customerLists.bulkAdd(payload.customerLists ?? [])
      await appDb.customers.bulkAdd(payload.customers ?? [])
      await appDb.visitLogs.bulkAdd(payload.visitLogs ?? [])
      await appDb.contactLogs.bulkAdd(payload.contactLogs ?? [])
      await appDb.visitSchedules.bulkAdd(payload.visitSchedules ?? [])
      await appDb.visitScheduleItems.bulkAdd(payload.visitScheduleItems ?? [])
      await appDb.messageTemplates.bulkAdd(payload.messageTemplates ?? defaultTemplates)
    })
    setActiveListId(payload.customerLists?.[0]?.id ?? '')
    if (options.markChanged) markLocalDataChanged()
    await refresh()
  }

  function markDriveSyncComplete() {
    const now = new Date().toISOString()
    localStorage.setItem(lastDriveSyncAtKey, now)
    setLastDriveSyncAt(now)
  }

  async function connectGoogleDrive() {
    if (!isGoogleDriveSyncConfigured()) {
      showToast('Google Client ID 설정이 필요합니다')
      return
    }
    setDriveSyncBusy(true)
    try {
      const token = await requestGoogleDriveToken([googleProfileScope, driveAppDataScope, driveFileScope], { prompt: 'consent' })
      const profile = await getGoogleUserProfile(token)
      const account = { ...profile, connectedAt: new Date().toISOString() }
      localStorage.setItem(googleDriveAccountKey, JSON.stringify(account))
      setGoogleDriveAccount(account)
      showToast(`${account.email} 계정으로 Google Drive를 연결했습니다`)
    } catch {
      showToast('Google 계정 연결에 실패했습니다. 팝업 차단과 OAuth 설정을 확인하세요')
    } finally {
      setDriveSyncBusy(false)
    }
  }

  function disconnectGoogleDrive() {
    localStorage.removeItem(googleDriveAccountKey)
    localStorage.removeItem(lastDriveSyncAtKey)
    setGoogleDriveAccount(null)
    setLastDriveSyncAt('')
    showToast('이 기기의 Google Drive 연결 정보를 삭제했습니다')
  }

  function ensureGoogleDriveConnected() {
    if (googleDriveAccount) return true
    showToast('먼저 Google 계정으로 연결하세요')
    return false
  }

  async function syncGoogleDrive() {
    if (!isGoogleDriveSyncConfigured()) {
      showToast('Google Client ID 설정이 필요합니다')
      return
    }
    if (!ensureGoogleDriveConnected()) return
    setDriveSyncBusy(true)
    try {
      const token = await requestGoogleDriveToken([driveAppDataScope], { prompt: '' })
      const localPayload = await buildBackupPayload()
      const syncFile = await findAppDataSyncFile(token)
      if (!syncFile) {
        await createAppDataSyncFile(token, localPayload as Record<string, unknown>)
        markDriveSyncComplete()
        showToast('Google Drive 동기화 파일을 만들었습니다')
        return
      }

      const remotePayload = await downloadDriveJson<AppBackupPayload>(token, syncFile.id)
      const mergedPayload = mergeBackupPayloads(remotePayload, localPayload)
      await restoreBackupPayload(mergedPayload)
      await updateDriveJsonFile(token, syncFile.id, mergedPayload as Record<string, unknown>)
      markDriveSyncComplete()
      showToast('Google Drive 동기화를 완료했습니다')
    } catch {
      showToast('Google Drive 동기화에 실패했습니다. 로그인 권한과 설정을 확인하세요')
    } finally {
      setDriveSyncBusy(false)
    }
  }

  async function restoreFromGoogleDrive() {
    if (!isGoogleDriveSyncConfigured()) {
      showToast('Google Client ID 설정이 필요합니다')
      return
    }
    if (!ensureGoogleDriveConnected()) return
    const confirmed = window.confirm('현재 기기의 고객 데이터와 기록을 Google Drive 데이터로 교체할까요? 새 기기에서 처음 불러올 때 사용하는 기능입니다.')
    if (!confirmed) return
    setDriveSyncBusy(true)
    try {
      const token = await requestGoogleDriveToken([driveAppDataScope], { prompt: '' })
      const syncFile = await findAppDataSyncFile(token)
      if (!syncFile) {
        showToast('Google Drive에 동기화 파일이 없습니다')
        return
      }
      const remotePayload = await downloadDriveJson<AppBackupPayload>(token, syncFile.id)
      await restoreBackupPayload(remotePayload)
      markDriveSyncComplete()
      showToast('Google Drive 데이터를 이 기기에 불러왔습니다')
    } catch {
      showToast('Google Drive 데이터 가져오기에 실패했습니다. 로그인 권한과 설정을 확인하세요')
    } finally {
      setDriveSyncBusy(false)
    }
  }

  async function saveGoogleDriveSnapshot() {
    if (!isGoogleDriveSyncConfigured()) {
      showToast('Google Client ID 설정이 필요합니다')
      return
    }
    if (!ensureGoogleDriveConnected()) return
    setDriveSyncBusy(true)
    try {
      const token = await requestGoogleDriveToken([driveAppDataScope], { prompt: '' })
      const payload = await buildBackupPayload()
      const syncFile = await findAppDataSyncFile(token)
      if (syncFile) {
        await updateDriveJsonFile(token, syncFile.id, payload as Record<string, unknown>)
      } else {
        await createAppDataSyncFile(token, payload as Record<string, unknown>)
      }
      markDriveSyncComplete()
      showToast('현재 기기 데이터를 Google Drive에 저장했습니다')
    } catch {
      showToast('Google Drive 저장에 실패했습니다. 로그인 권한과 설정을 확인하세요')
    } finally {
      setDriveSyncBusy(false)
    }
  }

  async function exportBackupToGoogleDrive() {
    if (!isGoogleDriveSyncConfigured()) {
      showToast('Google Client ID 설정이 필요합니다')
      return
    }
    if (!ensureGoogleDriveConnected()) return
    setDriveSyncBusy(true)
    try {
      const token = await requestGoogleDriveToken([driveFileScope], { prompt: '' })
      await createVisibleDriveBackup(token, await buildBackupPayload() as Record<string, unknown>)
      const now = new Date().toISOString()
      localStorage.setItem('lastBackupAt', now)
      setLastBackupAt(now)
      showToast('Google Drive에 백업 파일을 내보냈습니다')
    } catch {
      showToast('Google Drive 백업에 실패했습니다. 로그인 권한과 설정을 확인하세요')
    } finally {
      setDriveSyncBusy(false)
    }
  }

  async function deleteCustomerList(list: CustomerList) {
    const summary = renderListSummary(list)
    const confirmed = window.confirm(
      `${list.name} 고객리스트를 삭제할까요?\n\n고객 ${summary.total}명, 방문 로그 ${summary.visits}건, 문자 로그 ${summary.messages}건, 오늘 스케줄이 함께 삭제됩니다.`,
    )
    if (!confirmed) return

    const remainingLists = customerLists.filter((entry) => entry.id !== list.id)
    await appDb.transaction('rw', [appDb.customerLists, appDb.customers, appDb.visitLogs, appDb.contactLogs, appDb.visitSchedules, appDb.visitScheduleItems], async () => {
      await Promise.all([
        appDb.visitScheduleItems.where('customerListId').equals(list.id).delete(),
        appDb.visitSchedules.where('customerListId').equals(list.id).delete(),
        appDb.contactLogs.where('customerListId').equals(list.id).delete(),
        appDb.visitLogs.where('customerListId').equals(list.id).delete(),
        appDb.customers.where('customerListId').equals(list.id).delete(),
        appDb.customerLists.delete(list.id),
      ])
    })

    if (activeListId === list.id) {
      setActiveListId(remainingLists[0]?.id ?? '')
    }
    if (activeCustomers.some((customer) => customer.id === selectedCustomerId)) {
      setSelectedCustomerId('')
    }
    markLocalDataChanged()
    await refresh()
    showToast(`${list.name} 고객리스트를 삭제했습니다`)
  }

  function openNewCustomerSheet() {
    if (!activeList) {
      showToast('고객리스트를 먼저 선택하세요')
      return
    }
    setCustomerForm(blankCustomerForm())
    setEditingCustomerId('new')
  }

  function openEditCustomerSheet(customer: Customer) {
    setCustomerForm(customerToForm(customer))
    setEditingCustomerId(customer.id)
  }

  function closeCustomerSheet() {
    setEditingCustomerId(null)
    setCustomerForm(blankCustomerForm())
  }

  async function saveCustomerForm() {
    if (!activeList) {
      showToast('고객리스트를 먼저 선택하세요')
      return
    }
    const name = customerForm.name.trim()
    const phoneNumber = customerForm.phoneNumber.trim()
    const address = customerForm.address.trim()
    const birthDate = parseBirthDate(customerForm.birthDate)
    const notes = customerForm.notes.trim()
    if (!name) {
      showToast('고객 이름을 입력하세요')
      return
    }
    if (!phoneNumber && !address) {
      showToast('연락처 또는 주소 중 하나는 입력하세요')
      return
    }
    const now = new Date().toISOString()
    if (editingCustomerId === 'new') {
      await appDb.customers.add({
        id: makeId('customer'),
        customerListId: activeList.id,
        name,
        phoneNumber,
        address,
        birthDate: birthDate || undefined,
        notes,
        region: address ? extractRegion(address) : '주소 없음',
        status: 'open',
        createdAt: now,
        updatedAt: now,
      })
      showToast(`${name} 고객을 추가했습니다`)
    } else if (editingCustomerId) {
      const existing = customers.find((customer) => customer.id === editingCustomerId)
      const shouldClearCoordinates = existing?.address.trim() !== address
      await appDb.customers.update(editingCustomerId, {
        name,
        phoneNumber,
        address,
        birthDate: birthDate || undefined,
        notes,
        region: address ? extractRegion(address) : '주소 없음',
        updatedAt: now,
        ...(shouldClearCoordinates ? { latitude: undefined, longitude: undefined, coordinateSource: undefined, geocodedAt: undefined } : {}),
      })
      showToast(`${name} 고객 정보를 수정했습니다`)
    }
    closeCustomerSheet()
    markLocalDataChanged()
    await refresh()
  }

  async function saveCustomerNote() {
    if (!noteCustomer) return
    const body = noteText.trim()
    if (!body) {
      showToast('메모 내용을 입력하세요')
      return
    }
    await addTouchLog(noteCustomer, 'note', 'saved', body)
    setNoteCustomerId(null)
    setNoteText('')
    await refresh()
    showToast(`${noteCustomer.name} 메모를 저장했습니다`)
  }

  function appendNotePreset(preset: string) {
    setNoteText((current) => {
      const trimmed = current.trim()
      return trimmed ? `${trimmed}\n${preset}` : preset
    })
  }

  function dismissInstallGuide() {
    localStorage.setItem(installGuideDismissedKey, 'true')
    setShowInstallGuide(false)
  }

  async function installPwa() {
    if (!installPrompt) {
      setShowInstallGuide(true)
      return
    }
    await installPrompt.prompt()
    const choice = await installPrompt.userChoice
    setInstallPrompt(null)
    if (choice.outcome === 'accepted') {
      localStorage.setItem(installGuideDismissedKey, 'true')
      setShowInstallGuide(false)
      setIsStandalone(true)
      showToast('홈화면 앱 설치가 시작되었습니다')
    }
  }

  function renderListSummary(list: CustomerList) {
    const listCustomers = customers.filter((customer) => customer.customerListId === list.id)
    const open = listCustomers.filter((customer) => customer.status === 'open').length
    const visits = visitLogs.filter((log) => log.customerListId === list.id).length
    const messages = contactLogs.filter((log) => log.customerListId === list.id).length
    return { total: listCustomers.length, open, visits, messages }
  }

  function customerHistory(customer: Customer) {
    const visitEntries = visitLogs
      .filter((log) => log.customerId === customer.id)
      .map((log) => ({
        id: log.id,
        at: log.visitedAt,
        title: '완료 처리',
        detail: log.memo || '고객 서비스 완료',
        tone: 'green' as const,
      }))
    const touchEntries = contactLogs
      .filter((log) => log.customerId === customer.id)
      .map((log) => ({
        id: log.id,
        at: log.createdAt,
        title: contactLogTitle(log),
        detail: log.messageBody || contactLogDetail(log),
        tone: contactLogTone(log),
      }))
    return [...visitEntries, ...touchEntries].sort((a, b) => new Date(b.at).getTime() - new Date(a.at).getTime())
  }

  function contactLogTitle(log: ContactLog) {
    const labels: Record<ContactLog['type'], string> = {
      call: '전화 시도',
      manualSms: '문자 시도',
      templateSms: '템플릿 문자 시도',
      note: '상담 메모',
      statusComplete: '완료 처리',
      statusReopen: '완료 취소',
    }
    return labels[log.type]
  }

  function contactLogDetail(log: ContactLog) {
    if (log.type === 'call') return '전화 앱 열기'
    if (log.type === 'manualSms') return '문자 앱 열기'
    if (log.type === 'templateSms') return '템플릿 복사 후 문자 앱 열기'
    if (log.type === 'statusComplete') return '고객 서비스 완료'
    if (log.type === 'statusReopen') return '다시 활성화'
    return log.result
  }

  function contactLogTone(log: ContactLog): 'green' | 'orange' | 'blue' {
    if (log.type === 'statusComplete') return 'green'
    if (log.type === 'statusReopen') return 'blue'
    return 'orange'
  }

  function latestHistory(customer: Customer) {
    return customerHistory(customer)[0]
  }

  return (
    <main className="sales-app">
      <header className="app-header">
        {tab === 'customers' || tab === 'logs' ? (
          <label className="header-search">
            <Search size={17} />
            <input
              value={customerSearch}
              onChange={(event) => setCustomerSearch(event.target.value)}
              placeholder="이름·전화·주소 검색"
              type="search"
            />
          </label>
        ) : <span />}
        <button className="icon-button" type="button" onClick={() => setTab('settings')} aria-label="설정">
          <Settings size={22} />
        </button>
      </header>

      {activeList && (
        <section className="active-list">
          <div>
            <strong>{activeList.name}</strong>
            <span>{activeList.companyName} · {activeList.sourceFileName}</span>
          </div>
          <button type="button" onClick={() => setTab('customers')}>변경</button>
        </section>
      )}

      <section className="content">
        {tab === 'today' && renderToday()}
        {tab === 'customers' && renderCustomers()}
        {tab === 'import' && renderImport()}
        {tab === 'logs' && renderLogs()}
        {tab === 'settings' && renderSettings()}
      </section>

      <nav className="tabbar" aria-label="하단 메뉴">
        <TabButton active={tab === 'today'} icon={<Route size={21} />} label="오늘" onClick={() => setTab('today')} />
        <TabButton active={tab === 'customers'} icon={<ListFilter size={21} />} label="고객" onClick={() => setTab('customers')} />
        <TabButton active={tab === 'import'} icon={<Upload size={21} />} label="가져오기" onClick={() => setTab('import')} />
        <TabButton active={tab === 'logs'} icon={<CalendarCheck size={21} />} label="기록" onClick={() => setTab('logs')} />
      </nav>

      {messageCustomerId && renderMessageSheet()}
      {historyCustomer && renderHistorySheet(historyCustomer)}
      {noteCustomer && renderNoteSheet(noteCustomer)}
      {metricSheet && renderMetricSheet(metricSheet)}
      {editingCustomerId && renderCustomerEditor()}
      {showInstallGuide && renderInstallGuide()}
      {toast && <div className="toast">{toast}</div>}
    </main>
  )

  function renderCustomerEditor() {
    const isNew = editingCustomerId === 'new'
    return (
      <div className="sheet-backdrop" role="presentation" onClick={closeCustomerSheet}>
        <section className="message-sheet" role="dialog" aria-label={isNew ? '고객 추가' : '고객 수정'} onClick={(event) => event.stopPropagation()}>
          <div className="sheet-handle" />
          <div className="panel-title">
            <div>
              <h2>{isNew ? '고객 추가' : '고객 수정'}</h2>
              <span>{activeList?.name ?? '고객리스트 없음'}</span>
            </div>
            <button className="sheet-close" type="button" onClick={closeCustomerSheet}>닫기</button>
          </div>
          <div className="form-panel">
            <input value={customerForm.name} onChange={(event) => setCustomerForm({ ...customerForm, name: event.target.value })} placeholder="고객 이름" />
            <input value={customerForm.phoneNumber} onChange={(event) => setCustomerForm({ ...customerForm, phoneNumber: event.target.value })} placeholder="연락처" />
            <input value={customerForm.address} onChange={(event) => setCustomerForm({ ...customerForm, address: event.target.value })} placeholder="주소" />
            <input value={customerForm.birthDate} onChange={(event) => setCustomerForm({ ...customerForm, birthDate: event.target.value })} placeholder="생년월일 예: 19800101" />
            <textarea value={customerForm.notes} onChange={(event) => setCustomerForm({ ...customerForm, notes: event.target.value })} placeholder="메모" />
            <button className="primary full" type="button" onClick={() => void saveCustomerForm()}><Save size={18} /> 저장</button>
          </div>
        </section>
      </div>
    )
  }

  function renderNoteSheet(customer: Customer) {
    return (
      <div className="sheet-backdrop" role="presentation" onClick={() => setNoteCustomerId(null)}>
        <section className="message-sheet" role="dialog" aria-label={`${customer.name} 메모 추가`} onClick={(event) => event.stopPropagation()}>
          <div className="sheet-handle" />
          <div className="panel-title">
            <div>
              <h2>상담 메모</h2>
              <span>{customer.name}</span>
            </div>
            <button className="sheet-close" type="button" onClick={() => setNoteCustomerId(null)}>닫기</button>
          </div>
          <div className="form-panel">
            <div className="preset-grid">
              {notePresets.map((preset) => (
                <button className="secondary" type="button" key={preset} onClick={() => appendNotePreset(preset)}>
                  {preset.replace(': ', '')}
                </button>
              ))}
            </div>
            <textarea value={noteText} onChange={(event) => setNoteText(event.target.value)} placeholder="고객 대응 내용을 입력하세요" />
            <button className="primary full" type="button" onClick={() => void saveCustomerNote()}><Save size={18} /> 메모 저장</button>
          </div>
        </section>
      </div>
    )
  }

  function renderHistorySheet(customer: Customer) {
    const history = customerHistory(customer)
    return (
      <div className="sheet-backdrop" role="presentation" onClick={() => setHistoryCustomerId(null)}>
        <section className="message-sheet" role="dialog" aria-label={`${customer.name} 히스토리`} onClick={(event) => event.stopPropagation()}>
          <div className="sheet-handle" />
          <div className="panel-title">
            <div>
              <h2>{customer.name}</h2>
              <span>{customer.phoneNumber || '연락처 없음'}</span>
            </div>
            <button className="sheet-close" type="button" onClick={() => setHistoryCustomerId(null)}>닫기</button>
          </div>
          <div className="history-actions">
            <button type="button" onClick={() => openEditCustomerSheet(customer)}><Pencil size={17} /> 수정</button>
            <button type="button" onClick={() => { setNoteText(''); setNoteCustomerId(customer.id) }}><Plus size={17} /> 메모</button>
          </div>
          <div className="history-list">
            {history.length ? history.map((entry) => (
              <article className="history-item" key={entry.id}>
                <span className={`pill ${entry.tone}`}>{entry.title}</span>
                <strong>{formatTime(entry.at)}</strong>
                <small>{entry.detail}</small>
              </article>
            )) : <EmptyState text="아직 고객 터치 이력이 없습니다." />}
          </div>
        </section>
      </div>
    )
  }

  function renderMetricSheet(sheet: MetricSheet) {
    return (
      <div className="sheet-backdrop" role="presentation" onClick={() => setMetricSheet(null)}>
        <section className="message-sheet" role="dialog" aria-label={sheet.title} onClick={(event) => event.stopPropagation()}>
          <div className="sheet-handle" />
          <div className="panel-title">
            <div>
              <h2>{sheet.title}</h2>
              <span>{sheet.customers.length}명</span>
            </div>
            <button className="sheet-close" type="button" onClick={() => setMetricSheet(null)}>닫기</button>
          </div>
          <div className="metric-customer-list">
            {sheet.customers.length ? sheet.customers.map((customer) => (
              <button
                type="button"
                key={customer.id}
                onClick={() => {
                  setMetricSheet(null)
                  setHistoryCustomerId(customer.id)
                }}
              >
                <strong>{customer.name}</strong>
                <span>{customer.address || '주소 없음'}</span>
              </button>
            )) : <EmptyState text="표시할 고객이 없습니다." />}
          </div>
        </section>
      </div>
    )
  }

  function renderInstallGuide() {
    const isIos = isIosDevice()
    return (
      <div className="sheet-backdrop" role="presentation" onClick={dismissInstallGuide}>
        <section className="install-sheet" role="dialog" aria-label="홈화면 추가 안내" onClick={(event) => event.stopPropagation()}>
          <div className="sheet-handle" />
          <div className="install-title">
            <img src={`${import.meta.env.BASE_URL}apple-touch-icon.png`} alt="" />
            <div>
              <h2>홈화면에 추가</h2>
              <span>영업도우미</span>
            </div>
          </div>
          <p>{isIos ? 'Safari 공유 버튼을 누른 뒤 홈 화면에 추가를 선택하세요.' : '설치하면 브라우저 주소창 없이 앱처럼 실행됩니다.'}</p>
          <div className="install-actions">
            {installPrompt && (
              <button className="primary full" type="button" onClick={() => void installPwa()}>
                <Download size={18} />
                앱 설치
              </button>
            )}
            <button className="secondary full" type="button" onClick={dismissInstallGuide}>닫기</button>
          </div>
        </section>
      </div>
    )
  }

  function renderMessageSheet() {
    const customer = customers.find((entry) => entry.id === messageCustomerId)
    if (!customer) return null
    return (
      <div className="sheet-backdrop" role="presentation" onClick={() => setMessageCustomerId(null)}>
        <section className="message-sheet" role="dialog" aria-label={`${customer.name} 문자 보내기`} onClick={(event) => event.stopPropagation()}>
          <div className="sheet-handle" />
          <div className="panel-title">
            <div>
              <h2>문자 보내기</h2>
              <span>{customer.name} · {customer.phoneNumber || '연락처 없음'}</span>
            </div>
            <button className="sheet-close" type="button" onClick={() => setMessageCustomerId(null)}>닫기</button>
          </div>
          <div className="message-options">
            <button type="button" onClick={() => { setMessageCustomerId(null); void sendManualSms(customer) }}>
              <MessageSquareText size={18} />
              사용자 문자보내기
              <small>본문 자동 입력 없이 문자 앱을 엽니다</small>
            </button>
            {templates.map((template) => (
              <button type="button" key={template.id} onClick={() => { setMessageCustomerId(null); void sendTemplateSms(customer, template) }}>
                <Clipboard size={18} />
                {template.title}
                <small>{fillTemplate(template.body, customer)}</small>
              </button>
            ))}
          </div>
        </section>
      </div>
    )
  }

  function renderToday() {
    const targetList = todayMode === 'schedule' ? pendingScheduleCustomers : nearestCustomers
    return (
      <>
        <div className="segmented four">
          {(['schedule', 'nearest', 'region', 'map'] as TodayMode[]).map((mode) => (
            <button key={mode} className={todayMode === mode ? 'active' : ''} type="button" onClick={() => setTodayMode(mode)}>
              {modeLabel(mode)}
            </button>
          ))}
        </div>
        <section className="metric-grid">
          <Metric value={remainingCustomers.length} label="남은 고객" onClick={() => setMetricSheet({ title: '남은 고객', customers: remainingCustomers })} />
          <Metric value={touchedCustomers.length} label="터치 고객" onClick={() => setMetricSheet({ title: '터치 고객', customers: touchedCustomers })} />
          <Metric value={doneCustomers.length} label="완료 고객" onClick={() => setMetricSheet({ title: '완료 고객', customers: doneCustomers })} />
        </section>

        {todayMode === 'region' && renderRegionGroups()}
        {todayMode === 'map' && renderMap(targetList)}
        {todayMode !== 'region' && todayMode !== 'map' && (
          <>
            <section className="panel">
              <PanelTitle title={todayMode === 'schedule' ? '오늘 스케줄 전체' : '남은 고객'} meta={`${targetList.length}명`} />
              {targetList.length ? (
                <div className="list-stack">
                  {targetList.map((customer) => (
                    <HeroCustomer key={customer.id} customer={customer} badge={todayMode === 'schedule' ? '오늘 스케줄' : '가까운 순'} />
                  ))}
                </div>
              ) : <EmptyState text="표시할 고객이 없습니다." />}
            </section>
          </>
        )}
      </>
    )
  }

  function renderCustomers() {
    const searchActive = customerSearch.trim().length > 0
    const customerScope = searchActive ? searchedCustomers : activeCustomers
    const filtered =
      listFilter === 'open'
        ? remainingCustomers.filter((customer) => customerMatchesSearch(customer, customerSearch))
        : listFilter === 'done'
          ? customerScope.filter((customer) => customer.status === 'done')
          : customerScope
    const showFlatCustomerList = listFilter !== 'age'
    return (
      <>
        <section className="panel">
          <PanelTitle title="가져온 고객리스트" meta={`${customerLists.length}개`} />
          <div className="list-stack">
            {customerLists.map((list) => {
              const summary = renderListSummary(list)
              return (
                <article className={`list-card ${list.id === activeListId ? 'selected' : ''}`} key={list.id}>
                  <button type="button" onClick={() => setActiveListId(list.id)}>
                    <strong>{list.name}</strong>
                    <span>{list.companyName} · {list.sourceFileName}</span>
                    <small>총 {summary.total}명 · 미방문 {summary.open}명 · 방문 {summary.visits}건 · 문자 {summary.messages}건</small>
                  </button>
                  <button className="danger-icon" type="button" aria-label={`${list.name} 삭제`} onClick={() => void deleteCustomerList(list)}>
                    <Trash2 size={20} />
                  </button>
                </article>
              )
            })}
          </div>
        </section>

        <section className="panel">
          <PanelTitle title="오늘 스케줄" meta={`${activeScheduleItems.length}명`} />
          <div className="list-stack">
            {activeScheduleItems.map((item) => {
              const customer = activeCustomers.find((entry) => entry.id === item.customerId)
              if (!customer) return null
              return (
                <div className="schedule-row" key={item.id}>
                  <span>{item.orderIndex}</span>
                  <div>
                    <strong>{customer.name}</strong>
                    <small>{displayRegion(customer)} · {item.status}</small>
                  </div>
                  <button className="danger-icon" type="button" aria-label={`${customer.name} 스케줄 삭제`} onClick={() => void removeScheduleItem(item, customer)}>
                    <Trash2 size={20} />
                  </button>
                </div>
              )
            })}
          </div>
          <button className="secondary full" type="button" onClick={sortScheduleByDistance}>가까운 순 정렬</button>
        </section>

        {renderMap(customerScope, { title: '고객 위치 지도', subtitle: searchActive ? '검색 결과 기준' : '전체 고객 기준', showMissingList: true })}

        <section className="panel form-panel">
          <PanelTitle title="지도 위치 표시" meta={`표시 가능 ${trustedCoordinateCount}/${activeCustomers.length}명`} />
          <p className="backup-note">고객 주소를 지도 핀으로 표시할 수 있게 준비합니다. 많은 주소를 한 번에 처리하면 지도 서비스가 막을 수 있어 1초에 1명씩 천천히 확인합니다.</p>
          {geocodeProgress.running && (
            <div className="geocode-progress">
              <div>
                <strong>{geocodeProgress.done}/{geocodeProgress.total}</strong>
                <span>{geocodeProgress.current ? `${geocodeProgress.current} 위치 확인 중` : '위치 확인 중'}</span>
              </div>
              <progress value={geocodeProgress.done} max={geocodeProgress.total} />
            </div>
          )}
          <button className="secondary full" type="button" disabled={geocodeProgress.running || geocodableCustomers.length === 0} onClick={() => void geocodeActiveList()}>
            <Navigation size={18} />
            {geocodeProgress.running ? '위치 확인 중' : `고객 위치 지도에 표시 (${geocodableCustomers.length}명)`}
          </button>
        </section>

        <div className="segmented four">
          <button className={listFilter === 'open' ? 'active' : ''} type="button" onClick={() => setListFilter('open')}>미방문</button>
          <button className={listFilter === 'done' ? 'active' : ''} type="button" onClick={() => setListFilter('done')}>완료</button>
          <button className={listFilter === 'all' ? 'active' : ''} type="button" onClick={() => setListFilter('all')}>전체</button>
          <button className={listFilter === 'age' ? 'active' : ''} type="button" onClick={() => setListFilter('age')}>나이별</button>
        </div>

        {showFlatCustomerList ? (
          <section className="panel customer-list-panel">
            <PanelTitle title="고객 목록" meta={searchActive ? `${filtered.length}/${activeCustomers.length}명` : `${filtered.length}명`} />
            <div className="list-toolbar">
              {renderDisplayModeControl()}
              <button className="primary customer-add-button" type="button" onClick={openNewCustomerSheet}><Plus size={18} /> 고객 직접 추가</button>
            </div>
            {filtered.length ? (
              <div className={`customer-collection ${displayMode === 'cards' ? 'view-grid' : 'view-list'}`}>
                {filtered.map((customer) => (
                <CustomerRow key={customer.id} customer={customer} showAdd />
                ))}
              </div>
            ) : <EmptyState text="검색 결과가 없습니다." />}
          </section>
        ) : renderAgeGroups(customerScope)}
      </>
    )
  }

  function renderImport() {
    return (
      <>
        <section className="panel form-panel">
          <PanelTitle title="CSV 가져오기" meta="헤더 자동 인식" />
          <label className="file-drop">
            <FileSpreadsheet size={26} />
            <span>{importSourceFile || 'CSV 파일 선택'}</span>
            <input type="file" accept=".csv,text/csv" onChange={(event) => event.target.files?.[0] && handleCsvFile(event.target.files[0])} />
          </label>
          <input value={importCompany} onChange={(event) => setImportCompany(event.target.value)} placeholder="고객사 이름을 입력하세요" />
          <input value={importListName} onChange={(event) => setImportListName(event.target.value)} placeholder="예: 7월 강남 방문 리스트" />
        </section>

        {csv && (
          <section className="panel form-panel">
            <PanelTitle title="컬럼 매핑 확인" meta={`${csv.rows.length}행`} />
            {(Object.keys(csv.mapping) as FieldKey[]).map((field) => (
              <label className="field-map" key={field}>
                <span>{fieldLabel(field)}</span>
                <select
                  value={csv.mapping[field] ?? ''}
                  onChange={(event) => setCsv({ ...csv, mapping: { ...csv.mapping, [field]: event.target.value === '' ? null : Number(event.target.value) } })}
                >
                  <option value="">선택 안 함</option>
                  {csv.headers.map((header, index) => (
                    <option value={index} key={`${header}-${index}`}>{header}</option>
                  ))}
                </select>
              </label>
            ))}
            <button className="primary full" type="button" onClick={saveImportedList}>고객리스트로 저장</button>
          </section>
        )}
      </>
    )
  }

  function renderLogs() {
    const searchActive = customerSearch.trim().length > 0
    const logCustomers = searchActive ? searchedCustomers : activeCustomers
    const logTouchedCustomers = logCustomers.filter((customer) => customerHistory(customer).length > 0)
    const logDoneCustomers = logCustomers.filter((customer) => customer.status === 'done')
    const cumulativeHistory = logCustomers
      .flatMap((customer) => customerHistory(customer).map((entry) => ({ ...entry, customer })))
      .sort((a, b) => new Date(b.at).getTime() - new Date(a.at).getTime())

    return (
      <>
        <section className="metric-grid">
          <Metric value={logCustomers.length} label="전체 고객" onClick={() => setMetricSheet({ title: '전체 고객', customers: logCustomers })} />
          <Metric value={logTouchedCustomers.length} label="터치 고객" onClick={() => setMetricSheet({ title: '터치 고객', customers: logTouchedCustomers })} />
          <Metric value={logDoneCustomers.length} label="완료 고객" onClick={() => setMetricSheet({ title: '완료 고객', customers: logDoneCustomers })} />
        </section>
        <section className="panel log-list-panel">
          <PanelTitle title="고객별 히스토리" meta={searchActive ? `${logCustomers.length}/${activeCustomers.length}명` : (activeList?.name ?? '')} />
          <div className="list-toolbar">
            {renderDisplayModeControl()}
          </div>
          <div className={`history-customer-list ${displayMode === 'cards' ? 'view-grid' : 'view-list'}`}>
            {logCustomers.length ? logCustomers.map((customer) => {
              const latest = latestHistory(customer)
              return (
                <article className={`history-customer-row ${customer.status === 'done' ? 'highlight-done' : ''}`} key={customer.id} onClick={() => setHistoryCustomerId(customer.id)}>
                  <div>
                    <strong>{customer.name}</strong>
                    <span>{displayRegion(customer)} · {customer.phoneNumber || '연락처 없음'}</span>
                    <small>{latest ? `${latest.title} · ${formatTime(latest.at)}` : '아직 터치 이력 없음'}</small>
                  </div>
                  <span className={`pill ${customer.status === 'done' ? 'green' : latest ? 'orange' : ''}`}>{customer.status === 'done' ? '완료' : latest ? '진행중' : '미터치'}</span>
                </article>
              )
            }) : <EmptyState text="검색 결과가 없습니다." />}
          </div>
        </section>
        <section className="panel log-list-panel">
          <PanelTitle title="누적 터치/상담 히스토리" meta={`${cumulativeHistory.length}건`} />
          {cumulativeHistory.length ? (
            <div className={`history-event-list ${displayMode === 'cards' ? 'view-grid' : 'view-list'}`}>
              {cumulativeHistory.map((entry) => (
                <article className="history-event-row" key={entry.id} onClick={() => setHistoryCustomerId(entry.customer.id)}>
                  <div>
                    <span className={`pill ${entry.tone}`}>{entry.title}</span>
                    <strong>{entry.customer.name}</strong>
                    <small>{displayRegion(entry.customer)} · {formatTime(entry.at)}</small>
                    <p>{entry.detail}</p>
                  </div>
                  <button className="secondary" type="button" onClick={(event) => { event.stopPropagation(); setHistoryCustomerId(entry.customer.id) }}>
                    전체보기
                  </button>
                </article>
              ))}
            </div>
          ) : <EmptyState text="아직 누적 히스토리가 없습니다." />}
        </section>
      </>
    )
  }

  function renderSettings() {
    return (
      <>
        <section className="panel form-panel">
          <PanelTitle title="앱 설치" meta={isStandalone ? '홈화면 실행 중' : '웹 실행 중'} />
          <div className="install-inline">
            <img src={`${import.meta.env.BASE_URL}apple-touch-icon.png`} alt="" />
            <div>
              <strong>영업도우미</strong>
              <span>{isStandalone ? '현재 홈화면 앱 모드로 실행 중입니다.' : '홈화면에 추가하면 앱처럼 사용할 수 있습니다.'}</span>
            </div>
          </div>
          {!isStandalone && (
            <button className="secondary full" type="button" onClick={() => { localStorage.removeItem(installGuideDismissedKey); setShowInstallGuide(true) }}>
              <Download size={18} />
              홈화면 추가 안내
            </button>
          )}
        </section>
        <section className="panel form-panel">
          <PanelTitle title="문자 템플릿" meta={`${templates.length}개`} />
          <div className="list-stack">
            {templates.map((template) => (
              <article className="template-row" key={template.id}>
                {editingTemplateId === template.id ? (
                  <>
                    <input value={editingTemplateTitle} onChange={(event) => setEditingTemplateTitle(event.target.value)} placeholder="템플릿 제목" />
                    <textarea value={editingTemplateBody} onChange={(event) => setEditingTemplateBody(event.target.value)} placeholder="템플릿 내용" />
                    <div className="template-actions">
                      <button className="primary" type="button" onClick={() => void saveTemplateEdit()}><Save size={16} /> 저장</button>
                      <button className="secondary" type="button" onClick={closeTemplateEditor}>취소</button>
                    </div>
                  </>
                ) : (
                  <>
                    <strong>{template.title}{template.isDefault ? ' · 기본' : ''}</strong>
                    <span>{template.body}</span>
                    <div className="template-actions">
                      <button className="secondary" type="button" onClick={() => openTemplateEditor(template)}><Pencil size={16} /> 수정</button>
                      <button className="danger-icon text-danger" type="button" onClick={() => void deleteTemplate(template)}><Trash2 size={16} /> 삭제</button>
                    </div>
                  </>
                )}
              </article>
            ))}
          </div>
          <input value={newTemplateTitle} onChange={(event) => setNewTemplateTitle(event.target.value)} placeholder="템플릿 제목" />
          <textarea value={newTemplateBody} onChange={(event) => setNewTemplateBody(event.target.value)} placeholder="안녕하세요, {고객명}님." />
          <button className="primary full" type="button" onClick={addTemplate}><Plus size={18} /> 템플릿 추가</button>
        </section>
        <section className="panel form-panel">
          <PanelTitle
            title="Google Drive 동기화"
            meta={!isGoogleDriveSyncConfigured() ? '설정 필요' : googleDriveAccount ? (lastDriveSyncAt ? `최근 ${formatTime(lastDriveSyncAt)}` : '연결됨') : '연결 필요'}
          />
          <p className="backup-note">
            고객 데이터는 운영 서버가 아니라 사용자의 Google Drive 앱데이터 공간에 저장합니다. 평소에는 숨김 동기화 파일을 사용하고, 필요할 때 별도 백업 파일을 내보낼 수 있습니다.
          </p>
          {!isGoogleDriveSyncConfigured() && (
            <p className="backup-note">Google Cloud에서 Web OAuth Client ID를 만들고 `.env`에 `VITE_GOOGLE_CLIENT_ID`를 설정하면 사용할 수 있습니다.</p>
          )}
          {isGoogleDriveSyncConfigured() && googleDriveAccount && (
            <div className="drive-account">
              {googleDriveAccount.picture
                ? <img src={googleDriveAccount.picture} alt="" />
                : <UserRound size={22} />}
              <div>
                <strong>{googleDriveAccount.name}</strong>
                <span>{googleDriveAccount.email}</span>
              </div>
              <button className="secondary" type="button" onClick={disconnectGoogleDrive} disabled={driveSyncBusy}>
                <LogOut size={16} />
                해제
              </button>
            </div>
          )}
          {isGoogleDriveSyncConfigured() && googleDriveAccount && (
            <div className={`sync-status ${hasUnsyncedChanges ? 'needs-sync' : 'synced'}`}>
              <strong>{hasUnsyncedChanges ? '동기화 필요' : 'Drive 동기화 준비됨'}</strong>
              <span>
                {hasUnsyncedChanges
                  ? `마지막 로컬 변경: ${formatTime(lastLocalChangeAt)}`
                  : lastDriveSyncAt
                    ? `마지막 동기화: ${formatTime(lastDriveSyncAt)}`
                    : '아직 Drive 동기화 기록이 없습니다.'}
              </span>
            </div>
          )}
          {isGoogleDriveSyncConfigured() && !googleDriveAccount && (
            <button className="primary full" type="button" onClick={() => void connectGoogleDrive()} disabled={driveSyncBusy}>
              <UserRound size={18} />
              Google 계정으로 연결
            </button>
          )}
          <button className="primary full" type="button" onClick={() => void syncGoogleDrive()} disabled={driveSyncBusy || !isGoogleDriveSyncConfigured() || !googleDriveAccount}>
            <RefreshCw size={18} />
            Drive와 동기화
          </button>
          <button className="secondary full" type="button" onClick={() => void restoreFromGoogleDrive()} disabled={driveSyncBusy || !isGoogleDriveSyncConfigured() || !googleDriveAccount}>
            <Download size={18} />
            Drive 데이터를 이 기기에 가져오기
          </button>
          <button className="secondary full" type="button" onClick={() => void saveGoogleDriveSnapshot()} disabled={driveSyncBusy || !isGoogleDriveSyncConfigured() || !googleDriveAccount}>
            <Cloud size={18} />
            현재 기기 데이터를 Drive에 저장
          </button>
          <button className="secondary full" type="button" onClick={() => void exportBackupToGoogleDrive()} disabled={driveSyncBusy || !isGoogleDriveSyncConfigured() || !googleDriveAccount}>
            <Upload size={18} />
            Google Drive 백업 파일 만들기
          </button>
        </section>
        <section className="panel form-panel">
          <PanelTitle title="백업/복원" meta={lastBackupAt ? `최근 ${formatTime(lastBackupAt)}` : '백업 없음'} />
          <p className="backup-note">iPhone PWA는 사용자 조작 없이 파일 앱/iCloud Drive에 자동 저장하기 어렵습니다. 대신 7일 이상 백업이 없으면 앱 실행 시 알림을 띄우고, 아래 버튼으로 한 번에 JSON 백업을 저장합니다.</p>
          <button className="secondary full" type="button" onClick={exportBackup}><Download size={18} /> JSON 백업 내보내기</button>
          <button className="secondary full" type="button" onClick={() => backupInputRef.current?.click()}><Upload size={18} /> JSON 백업 가져오기</button>
          <input ref={backupInputRef} hidden type="file" accept="application/json,.json" onChange={(event) => event.target.files?.[0] && importBackup(event.target.files[0])} />
        </section>
      </>
    )
  }

  function renderMap(
    list: Customer[],
    options: { title?: string; subtitle?: string; showMissingList?: boolean } = {},
  ) {
    const mapList = list.filter(hasTrustedCoordinates)
    const selected = selectedCustomer && hasTrustedCoordinates(selectedCustomer) ? selectedCustomer : mapList[0]
    const path = mapList.map((customer) => [customer.latitude!, customer.longitude!] as [number, number])
    const pendingLocationCount = list.filter(needsMapLocationRefresh).length
    const missingAddressCount = list.filter((customer) => !isSearchableAddress(customer.address) && !hasTrustedCoordinates(customer)).length
    const missingCustomers = list.filter((customer) => !hasTrustedCoordinates(customer))
    const scheduledIds = new Set(activeScheduleItems.map((item) => item.customerId))
    return (
      <section className="panel map-panel">
        <PanelTitle title={options.title ?? '오늘 지도'} meta={`${mapList.length}/${list.length}명 표시`} />
        {options.subtitle && <p className="backup-note">{options.subtitle}</p>}
        <div className="map-frame">
          <button className="map-overlay-location" type="button" onClick={requestLocation}>
            <Navigation size={18} />
            내 위치
          </button>
          <MapContainer center={selected?.latitude && selected?.longitude ? [selected.latitude, selected.longitude] : location} zoom={13} scrollWheelZoom={false}>
            <MapFocus location={location} tick={mapFocusTick} />
            <MapFitToCustomers points={path} />
            <TileLayer attribution="&copy; OpenStreetMap" url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
            {hasUserLocation && (
              <Marker position={location} icon={userLocationIcon}>
                <Popup>내 위치</Popup>
              </Marker>
            )}
            {path.length > 1 && <Polyline positions={path} pathOptions={{ color: '#1f6feb', weight: 4, dashArray: '8 8' }} />}
            {mapList.map((customer, index) => (
              <Marker
                key={customer.id}
                position={[customer.latitude!, customer.longitude!]}
                icon={customerMapIcon(customer, customer.id === selectedCustomerId, scheduledIds.has(customer.id))}
                eventHandlers={{ click: () => setSelectedCustomerId(customer.id) }}
              >
                <Popup minWidth={220} closeButton>
                  {renderMapPopupCard(customer, index + 1, scheduledIds.has(customer.id))}
                </Popup>
              </Marker>
            ))}
          </MapContainer>
        </div>
        {geocodeProgress.running && (
          <div className="map-location-notice">
            <strong>고객 주소를 지도에 표시하는 중입니다</strong>
            <span>{geocodeProgress.done}/{geocodeProgress.total}명 확인 · {geocodeProgress.current || '주소 확인 중'}</span>
            <progress value={geocodeProgress.done} max={geocodeProgress.total} />
          </div>
        )}
        {!geocodeProgress.running && pendingLocationCount > 0 && (
          <div className="map-location-notice">
            <strong>{pendingLocationCount}명의 위치가 아직 지도에 표시되지 않았습니다</strong>
            <span>고객 주소를 확인해서 지도 핀으로 표시합니다. 한 번 준비되면 다음 실행 때도 저장된 위치를 사용합니다.</span>
            <button className="secondary full" type="button" onClick={() => void geocodeActiveList()}>
              <Navigation size={18} />
              고객 위치 지도에 표시
            </button>
          </div>
        )}
        {!geocodeProgress.running && missingAddressCount > 0 && (
          <div className="map-location-notice muted">
            <strong>{missingAddressCount}명은 주소가 없어 지도에 표시할 수 없습니다</strong>
            <span>고객 수정에서 주소를 입력하면 지도 표시 대상에 포함됩니다.</span>
          </div>
        )}
        {options.showMissingList && missingCustomers.length > 0 && (
          <div className="map-missing-list">
            <strong>지도에 표시되지 않은 고객</strong>
            <div>
              {missingCustomers.map((customer) => (
                <span key={customer.id}>{customer.name} · {mapMissingReason(customer)}</span>
              ))}
            </div>
          </div>
        )}
      </section>
    )
  }

  function renderMapPopupCard(customer: Customer, order: number, scheduled: boolean) {
    return (
      <div className="map-popup-card">
        <div>
          <strong>{order}. {customer.name}</strong>
          <span>{normalizeAddressForMapSearch(customer.address) || customer.address}</span>
          <small>{scheduled ? '오늘 스케줄 포함' : '스케줄 미포함'} · {statusLabel(customer.status)}</small>
        </div>
        <div className="map-popup-actions">
          <button type="button" onClick={() => void callCustomer(customer)}><PhoneCall size={15} /> 전화</button>
          <button type="button" onClick={() => setMessageCustomerId(customer.id)}><MessageSquareText size={15} /> 문자</button>
          <button type="button" onClick={() => navigateCustomer(customer)}><Navigation size={15} /> 길찾기</button>
        </div>
        <div className="map-popup-actions">
          <button type="button" onClick={() => setHistoryCustomerId(customer.id)}><CalendarCheck size={15} /> 이력</button>
          {customer.status === 'done'
            ? <button type="button" onClick={() => void reopenCustomer(customer)}><RotateCcw size={15} /> 완료취소</button>
            : <button type="button" onClick={() => void completeVisit(customer)}><Check size={15} /> 완료</button>}
        </div>
        {!scheduled && customer.status === 'open' && (
          <button className="map-popup-full" type="button" onClick={() => addSelectedToSchedule(customer)}>스케줄 추가</button>
        )}
      </div>
    )
  }

  function renderRegionGroups() {
    const groups = remainingCustomers.reduce<Record<string, Customer[]>>((acc, customer) => {
      const key = displayRegion(customer)
      acc[key] = [...(acc[key] ?? []), customer]
      return acc
    }, {})
    return (
      <section className="panel">
        <PanelTitle title="지역별 보기" meta={`${Object.keys(groups).length}개 지역`} />
        {Object.entries(groups).map(([region, group]) => (
          <div className="region-group" key={region}>
            <h2>{region}</h2>
            <div className="list-stack">
              {group.map((customer) => <CustomerRow key={customer.id} customer={customer} showAdd={false} />)}
            </div>
          </div>
        ))}
      </section>
    )
  }

  function renderAgeGroups(list: Customer[]) {
    const groups = list.reduce<Record<string, Customer[]>>((acc, customer) => {
      const key = ageGroup(customer)
      acc[key] = [...(acc[key] ?? []), customer]
      return acc
    }, {})
    const order = (label: string) => (label === '나이 미상' ? 999 : label === '10대 이하' ? 10 : Number(label.replace(/\D/g, '')) || 998)
    const entries = Object.entries(groups).sort(([a], [b]) => order(a) - order(b))
    return (
      <section className="panel">
        <PanelTitle title="나이별 보기" meta={`${entries.length}개 그룹`} />
        {entries.length ? entries.map(([group, groupCustomers]) => (
          <div className="region-group" key={group}>
            <h2>{group}</h2>
            <div className="list-stack">
              {groupCustomers.map((customer) => <CustomerRow key={customer.id} customer={customer} showAdd />)}
            </div>
          </div>
        )) : <EmptyState text="검색 결과가 없습니다." />}
      </section>
    )
  }

  function renderDisplayModeControl() {
    return (
      <div className="view-toggle" aria-label="표시 방식">
        <button className={displayMode === 'cards' ? 'active' : ''} type="button" onClick={() => changeDisplayMode('cards')}>
          <LayoutGrid size={17} />
          카드
        </button>
        <button className={displayMode === 'list' ? 'active' : ''} type="button" onClick={() => changeDisplayMode('list')}>
          <List size={17} />
          목록
        </button>
      </div>
    )
  }

  function HeroCustomer({ customer, badge }: { customer: Customer; badge: string }) {
    return (
      <article className={`hero-card ${customer.status === 'done' ? 'is-done' : ''}`}>
        <div className="chip-row">
          <span className="pill blue">{badge}</span>
          <span className="pill">{displayRegion(customer)}</span>
          <span className={hasTrustedCoordinates(customer) ? 'pill green' : 'pill orange'}>{customerDistanceLabel(customer)}</span>
          <span className={`pill ${customer.status === 'done' ? 'green' : customer.status === 'hold' ? 'orange' : 'blue'}`}>{statusLabel(customer.status)}</span>
        </div>
        <div>
          <h2>{customer.name}</h2>
          <p>{customer.address}</p>
          <small>{customer.notes}</small>
        </div>
        <ActionGrid customer={customer} />
        <div className="secondary-grid">
          <button className="secondary" type="button" onClick={() => setHistoryCustomerId(customer.id)}><CalendarCheck size={18} /> 히스토리</button>
          <button className="secondary" type="button" onClick={() => { setNoteText(''); setNoteCustomerId(customer.id) }}><Plus size={18} /> 메모</button>
          <button className="secondary" type="button" onClick={() => openEditCustomerSheet(customer)}><Pencil size={18} /> 수정</button>
        </div>
        {customer.status === 'done'
          ? <button className="secondary full" type="button" onClick={() => void reopenCustomer(customer)}><RotateCcw size={22} /> 완료취소</button>
          : <button className="complete full" type="button" onClick={() => void completeVisit(customer)}><Check size={22} /> 완료</button>}
      </article>
    )
  }

  function CustomerRow({ customer, showAdd }: { customer: Customer; showAdd: boolean }) {
    return (
      <article className={`customer-row ${customer.status === 'done' ? 'is-done' : ''}`} onClick={() => setSelectedCustomerId(customer.id)}>
        <div>
          <strong>{customer.name}</strong>
          <span>{displayRegion(customer)} · {customerDistanceLabel(customer)}</span>
          <small>{customer.address}</small>
          {customer.birthDate && <small>{birthDateLabel(customer)} · {ageGroup(customer)}</small>}
          {latestHistory(customer) && <small>최근: {latestHistory(customer)?.title} · {formatTime(latestHistory(customer)!.at)}</small>}
        </div>
        <span className={`pill ${customer.status === 'done' ? 'green' : customer.status === 'hold' ? 'orange' : 'blue'}`}>{statusLabel(customer.status)}</span>
        <ActionGrid customer={customer} />
        <div className="secondary-grid">
          <button className="secondary" type="button" onClick={() => setHistoryCustomerId(customer.id)}>히스토리</button>
          <button className="secondary" type="button" onClick={() => { setNoteText(''); setNoteCustomerId(customer.id) }}>메모</button>
          <button className="secondary" type="button" onClick={() => openEditCustomerSheet(customer)}>수정</button>
        </div>
        {showAdd && customer.status === 'open' && <button className="secondary full" type="button" onClick={() => addSelectedToSchedule(customer)}>스케줄 추가</button>}
        {customer.status === 'done'
          ? <button className="secondary full" type="button" onClick={() => void reopenCustomer(customer)}><RotateCcw size={18} /> 완료취소</button>
          : <button className="complete full" type="button" onClick={() => void completeVisit(customer)}><Check size={18} /> 완료</button>}
      </article>
    )
  }

  function ActionGrid({ customer }: { customer: Customer }) {
    return (
      <div className="action-grid">
        <button type="button" onClick={() => void callCustomer(customer)}><PhoneCall size={18} /> 전화</button>
        <button type="button" onClick={() => setMessageCustomerId(customer.id)}><MessageSquareText size={18} /> 문자</button>
        <button type="button" onClick={() => navigateCustomer(customer)}><Navigation size={18} /> 길찾기</button>
      </div>
    )
  }
}

function MapFocus({ location, tick }: { location: [number, number]; tick: number }) {
  const map = useMap()
  useEffect(() => {
    if (tick > 0) {
      map.flyTo(location, Math.max(map.getZoom(), 15), { duration: 0.7 })
    }
  }, [location, map, tick])
  return null
}

function MapFitToCustomers({ points }: { points: [number, number][] }) {
  const map = useMap()
  const lastSignatureRef = useRef('')

  useEffect(() => {
    const signature = points.map(([latitude, longitude]) => `${latitude.toFixed(6)},${longitude.toFixed(6)}`).join('|')
    if (signature === lastSignatureRef.current) return
    lastSignatureRef.current = signature
    if (!points.length) return
    if (points.length === 1) {
      map.setView(points[0], Math.max(map.getZoom(), 15), { animate: true })
      return
    }
    map.fitBounds(L.latLngBounds(points), { padding: [36, 36], maxZoom: 15, animate: true })
  }, [map, points])

  return null
}

function TabButton({ active, icon, label, onClick }: { active: boolean; icon: React.ReactNode; label: string; onClick: () => void }) {
  return (
    <button className={active ? 'active' : ''} type="button" onClick={onClick}>
      {icon}
      <span>{label}</span>
    </button>
  )
}

function Metric({ value, label, onClick }: { value: number; label: string; onClick?: () => void }) {
  return (
    <button className="metric" type="button" onClick={onClick}>
      <strong>{value}</strong>
      <span>{label}</span>
    </button>
  )
}

function PanelTitle({ title, meta }: { title: string; meta: string }) {
  return (
    <div className="panel-title">
      <h2>{title}</h2>
      <span>{meta}</span>
    </div>
  )
}

function EmptyState({ text }: { text: string }) {
  return <section className="empty-state"><Search size={32} />{text}</section>
}

function modeLabel(mode: TodayMode) {
  const labels: Record<TodayMode, string> = {
    schedule: '스케줄',
    nearest: '가까운 순',
    region: '지역별',
    map: '지도',
  }
  return labels[mode]
}

function fieldLabel(field: FieldKey) {
  const labels: Record<FieldKey, string> = {
    name: '고객명',
    phoneNumber: '연락처',
    address: '주소',
    birthDate: '생년월일',
    notes: '기타사항',
    latitude: '위도',
    longitude: '경도',
  }
  return labels[field]
}

function statusLabel(status: Customer['status']) {
  const labels: Record<Customer['status'], string> = {
    open: '활성',
    done: '완료',
    hold: '보류',
    needsGeocode: '주소확인',
  }
  return labels[status]
}

export default App
