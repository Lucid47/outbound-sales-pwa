import { useEffect, useMemo, useRef, useState } from 'react'
import Papa from 'papaparse'
import { useMap } from 'react-leaflet'
import { CircleMarker, MapContainer, Marker, Polyline, Popup, TileLayer } from 'react-leaflet'
import L from 'leaflet'
import {
  CalendarCheck,
  Check,
  Clipboard,
  Download,
  FileSpreadsheet,
  ListFilter,
  MessageSquareText,
  Navigation,
  Pencil,
  PhoneCall,
  Plus,
  RotateCcw,
  Route,
  Save,
  Search,
  Settings,
  Trash2,
  Upload,
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
import './App.css'

type TabKey = 'today' | 'customers' | 'import' | 'logs' | 'settings'
type TodayMode = 'schedule' | 'nearest' | 'region' | 'map'
type ListFilterKey = 'open' | 'done' | 'all'
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
  notes: string
}

type ParsedCsv = {
  headers: string[]
  rows: string[][]
  mapping: FieldMapping
}

type FieldKey = 'name' | 'phoneNumber' | 'address' | 'notes' | 'latitude' | 'longitude'
type FieldMapping = Record<FieldKey, number | null>

const installGuideDismissedKey = 'installGuideDismissed'
const defaultCenter: [number, number] = [37.5009, 127.0364]
const userLocationIcon = L.divIcon({
  className: 'user-location-pin',
  html: '<span></span>',
  iconSize: [32, 44],
  iconAnchor: [16, 44],
  popupAnchor: [0, -42],
})

const aliases: Record<FieldKey, string[]> = {
  name: ['고객명', '고객 이름', '이름', '성명', '거래처명', '회사명', 'name', 'customer', 'customername'],
  phoneNumber: ['연락처', '전화번호', '휴대폰', '핸드폰', '휴대전화', 'mobile', 'phone', 'tel', 'telephone'],
  address: ['주소', '방문주소', '사업장주소', '고객주소', 'address', 'addr', 'location'],
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
  return value.trim().toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '')
}

function detectMapping(headers: string[]): FieldMapping {
  const mapping: FieldMapping = { name: null, phoneNumber: null, address: null, notes: null, latitude: null, longitude: null }
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
  return phoneNumber.replace(/[^\d+]/g, '')
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
  const parts = address.split(/\s+/).filter(Boolean)
  if (parts.length >= 3) return `${parts[1]} ${parts[2]}`
  if (parts.length >= 2) return parts.slice(0, 2).join(' ')
  return '지역 미확인'
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
  return { name: '', phoneNumber: '', address: '', notes: '' }
}

function customerToForm(customer: Customer): CustomerForm {
  return {
    name: customer.name,
    phoneNumber: customer.phoneNumber,
    address: customer.address,
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

async function geocodeAddress(address: string) {
  const url = new URL('https://nominatim.openstreetmap.org/search')
  url.searchParams.set('format', 'jsonv2')
  url.searchParams.set('q', address)
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
  const [importCompany, setImportCompany] = useState('고객사 C')
  const [importListName, setImportListName] = useState('고객사 C - 7월 2차 방문 리스트')
  const [importSourceFile, setImportSourceFile] = useState('')
  const [newTemplateTitle, setNewTemplateTitle] = useState('')
  const [newTemplateBody, setNewTemplateBody] = useState('')
  const [messageCustomerId, setMessageCustomerId] = useState<string | null>(null)
  const [mapFocusTick, setMapFocusTick] = useState(0)
  const [lastBackupAt, setLastBackupAt] = useState<string>(() => localStorage.getItem('lastBackupAt') ?? '')
  const [isStandalone, setIsStandalone] = useState(() => isPwaStandalone())
  const [installPrompt, setInstallPrompt] = useState<BeforeInstallPromptEvent | null>(null)
  const [showInstallGuide, setShowInstallGuide] = useState(false)
  const [geocodeProgress, setGeocodeProgress] = useState<GeocodeProgress>({ running: false, done: 0, total: 0, failed: 0, current: '' })
  const [editingCustomerId, setEditingCustomerId] = useState<string | 'new' | null>(null)
  const [customerForm, setCustomerForm] = useState<CustomerForm>(() => blankCustomerForm())
  const [historyCustomerId, setHistoryCustomerId] = useState<string | null>(null)
  const [noteCustomerId, setNoteCustomerId] = useState<string | null>(null)
  const [noteText, setNoteText] = useState('')
  const backupInputRef = useRef<HTMLInputElement | null>(null)

  const activeList = customerLists.find((list) => list.id === activeListId) ?? customerLists[0]
  const activeCustomers = useMemo(() => customers.filter((customer) => customer.customerListId === activeList?.id), [customers, activeList])
  const activeVisits = useMemo(() => visitLogs.filter((log) => log.customerListId === activeList?.id), [visitLogs, activeList])
  const activeContacts = useMemo(() => contactLogs.filter((log) => log.customerListId === activeList?.id), [contactLogs, activeList])
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
  const geocodableCustomers = activeCustomers.filter((customer) => customer.address.trim() && !hasTrustedCoordinates(customer))
  const trustedCoordinateCount = activeCustomers.filter(hasTrustedCoordinates).length

  useEffect(() => {
    async function seedAndLoadInitialData() {
      const count = await appDb.customerLists.count()
      if (count === 0) {
        await appDb.transaction('rw', [appDb.customerLists, appDb.customers, appDb.visitSchedules, appDb.visitScheduleItems, appDb.visitLogs, appDb.messageTemplates], async () => {
          await appDb.customerLists.bulkAdd(sampleLists)
          await appDb.customers.bulkAdd(sampleCustomers)
          await appDb.visitSchedules.bulkAdd(sampleSchedules)
          if (sampleScheduleItems.length) await appDb.visitScheduleItems.bulkAdd(sampleScheduleItems)
          await appDb.visitLogs.bulkAdd(sampleVisitLogs)
          await appDb.messageTemplates.bulkAdd(defaultTemplates)
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
    await refresh()
    showToast(`${customer.name} 고객을 다시 활성화했습니다`)
  }

  async function sendManualSms(customer: Customer) {
    await addTouchLog(customer, 'manualSms', 'opened')
    await refresh()
    window.location.href = `sms:${cleanPhone(customer.phoneNumber)}`
  }

  async function sendTemplateSms(customer: Customer, template: MessageTemplate) {
    const body = fillTemplate(template.body, customer)
    try {
      await navigator.clipboard.writeText(body)
      showToast('템플릿 문자를 복사했습니다. 문자 앱에서 붙여넣어 전송하세요')
    } catch {
      showToast('본문 복사가 제한되었습니다. 템플릿 내용을 직접 복사하세요')
    }
    await addTouchLog(customer, 'templateSms', 'sentByUser', body, template.id)
    await refresh()
    window.location.href = `sms:${cleanPhone(customer.phoneNumber)}`
  }

  async function callCustomer(customer: Customer) {
    await addTouchLog(customer, 'call', 'opened')
    await refresh()
    window.location.href = `tel:${cleanPhone(customer.phoneNumber)}`
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

  function openTmapRoute(customer: Customer) {
    const goalName = encodeURIComponent(customer.address || customer.name)
    const goalX = customer.longitude
    const goalY = customer.latitude
    const tmapUrl = `tmap://route?goalx=${goalX}&goaly=${goalY}&goalname=${goalName}`
    openExternalApp(tmapUrl)
  }

  function openTmapSearch(customer: Customer) {
    const destination = customer.address.trim() || customer.name.trim()
    const encodedDestination = encodeURIComponent(destination)
    const tmapUrl = `tmap://?search=${encodedDestination}`
    showToast('정확한 좌표가 없어 티맵에서 주소를 검색합니다')
    openExternalApp(tmapUrl)
  }

  function openExternalApp(url: string) {
    window.location.href = url
  }

  function fillTemplate(templateBody: string, customer: Customer) {
    return templateBody
      .replaceAll('{고객명}', customer.name)
      .replaceAll('{고객사명}', activeList?.companyName ?? '')
      .replaceAll('{지역}', customer.region ?? '')
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
    const now = new Date().toISOString()
    const listId = makeId('list')
    const list: CustomerList = {
      id: listId,
      name: importListName.trim() || '새 고객리스트',
      companyName: importCompany.trim() || '고객사 미입력',
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
    await refresh()
    showToast(`${customer.name} 고객을 오늘 스케줄에 추가했습니다`)
  }

  async function removeScheduleItem(item: VisitScheduleItem, customer?: Customer) {
    const remainingItems = activeScheduleItems.filter((entry) => entry.id !== item.id)
    await appDb.transaction('rw', appDb.visitScheduleItems, async () => {
      await appDb.visitScheduleItems.delete(item.id)
      await Promise.all(remainingItems.map((entry, index) => appDb.visitScheduleItems.update(entry.id, { orderIndex: index + 1 })))
    })
    await refresh()
    showToast(`${customer?.name ?? '고객'}을 오늘 스케줄에서 삭제했습니다`)
  }

  async function geocodeActiveList() {
    if (geocodeProgress.running) return
    const targets = activeCustomers.filter((customer) => customer.address.trim() && !hasTrustedCoordinates(customer))
    if (!targets.length) {
      showToast('좌표변환이 필요한 고객이 없습니다')
      return
    }

    let failed = 0
    setGeocodeProgress({ running: true, done: 0, total: targets.length, failed: 0, current: '' })

    for (let index = 0; index < targets.length; index += 1) {
      const customer = targets[index]
      setGeocodeProgress({ running: true, done: index, total: targets.length, failed, current: customer.name })
      try {
        const result = await geocodeAddress(customer.address)
        if (result) {
          const now = new Date().toISOString()
          await appDb.customers.update(customer.id, {
            latitude: result.latitude,
            longitude: result.longitude,
            coordinateSource: 'geocoded',
            geocodedAt: now,
            updatedAt: now,
          })
        } else {
          failed += 1
        }
      } catch {
        failed += 1
      }
      setGeocodeProgress({ running: true, done: index + 1, total: targets.length, failed, current: customer.name })
      if (index < targets.length - 1) await wait(1100)
    }

    await refresh()
    setGeocodeProgress({ running: false, done: targets.length, total: targets.length, failed, current: '' })
    showToast(failed ? `좌표변환 완료: ${targets.length - failed}명 성공, ${failed}명 실패` : `${targets.length}명 좌표변환 완료`)
  }

  async function sortScheduleByDistance() {
    const sorted = activeScheduleItems
      .map((item) => ({ item, customer: activeCustomers.find((customer) => customer.id === item.customerId) }))
      .filter((entry): entry is { item: VisitScheduleItem; customer: Customer } => Boolean(entry.customer))
      .sort((a, b) => customerDistance(a.customer) - customerDistance(b.customer))
    await Promise.all(sorted.map((entry, index) => appDb.visitScheduleItems.update(entry.item.id, { orderIndex: index + 1 })))
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
    await refresh()
    showToast('문자 템플릿을 추가했습니다')
  }

  async function exportBackup() {
    const payload = {
      exportedAt: new Date().toISOString(),
      customerLists: await appDb.customerLists.toArray(),
      customers: await appDb.customers.toArray(),
      visitLogs: await appDb.visitLogs.toArray(),
      contactLogs: await appDb.contactLogs.toArray(),
      visitSchedules: await appDb.visitSchedules.toArray(),
      visitScheduleItems: await appDb.visitScheduleItems.toArray(),
      messageTemplates: await appDb.messageTemplates.toArray(),
    }
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
    await refresh()
    showToast('백업을 복원했습니다')
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
        notes,
        region: address ? extractRegion(address) : '주소 없음',
        updatedAt: now,
        ...(shouldClearCoordinates ? { latitude: undefined, longitude: undefined, coordinateSource: undefined, geocodedAt: undefined } : {}),
      })
      showToast(`${name} 고객 정보를 수정했습니다`)
    }
    closeCustomerSheet()
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
              <span>{customer.name} · {customer.phoneNumber}</span>
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
          <Metric value={remainingCustomers.length} label="남은 고객" />
          <Metric value={activeContacts.length + activeVisits.length} label="터치 이력" />
          <Metric value={activeCustomers.filter((customer) => customer.status === 'done').length} label="완료 고객" />
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
    const filtered =
      listFilter === 'open'
        ? remainingCustomers
        : listFilter === 'done'
          ? activeCustomers.filter((customer) => customer.status === 'done')
          : activeCustomers
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
                    <small>{customer.region} · {item.status}</small>
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

        <section className="panel form-panel">
          <PanelTitle title="주소 좌표변환" meta={`좌표 확보 ${trustedCoordinateCount}/${activeCustomers.length}명`} />
          <p className="backup-note">거리순과 지도 핀을 정확히 쓰기 위해 주소를 좌표로 변환해 저장합니다. OpenStreetMap Nominatim 정책에 맞춰 1초에 1명씩 천천히 처리합니다.</p>
          {geocodeProgress.running && (
            <div className="geocode-progress">
              <div>
                <strong>{geocodeProgress.done}/{geocodeProgress.total}</strong>
                <span>{geocodeProgress.current ? `${geocodeProgress.current} 변환 중` : '주소 변환 중'}</span>
              </div>
              <progress value={geocodeProgress.done} max={geocodeProgress.total} />
            </div>
          )}
          <button className="secondary full" type="button" disabled={geocodeProgress.running || geocodableCustomers.length === 0} onClick={() => void geocodeActiveList()}>
            <Navigation size={18} />
            {geocodeProgress.running ? '좌표변환 중' : `좌표변환 시작 (${geocodableCustomers.length}명)`}
          </button>
        </section>

        <div className="segmented">
          <button className={listFilter === 'open' ? 'active' : ''} type="button" onClick={() => setListFilter('open')}>미방문</button>
          <button className={listFilter === 'done' ? 'active' : ''} type="button" onClick={() => setListFilter('done')}>완료</button>
          <button className={listFilter === 'all' ? 'active' : ''} type="button" onClick={() => setListFilter('all')}>전체</button>
        </div>

        <section className="panel">
          <PanelTitle title="고객 목록" meta={`${filtered.length}명`} />
          <button className="primary full customer-add-button" type="button" onClick={openNewCustomerSheet}><Plus size={18} /> 고객 직접 추가</button>
          <div className="list-stack">
            {filtered.map((customer) => (
              <CustomerRow key={customer.id} customer={customer} showAdd />
            ))}
          </div>
        </section>
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
          <input value={importCompany} onChange={(event) => setImportCompany(event.target.value)} placeholder="고객사 이름" />
          <input value={importListName} onChange={(event) => setImportListName(event.target.value)} placeholder="고객리스트 이름" />
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
    const doneCustomers = activeCustomers.filter((customer) => customer.status === 'done')
    const touchedCustomers = activeCustomers.filter((customer) => customerHistory(customer).length > 0)
    return (
      <>
        <section className="metric-grid">
          <Metric value={activeCustomers.length} label="전체 고객" />
          <Metric value={touchedCustomers.length} label="터치 고객" />
          <Metric value={doneCustomers.length} label="완료 고객" />
        </section>
        <section className="panel">
          <PanelTitle title="고객별 히스토리" meta={activeList?.name ?? ''} />
          <div className="list-stack">
            {activeCustomers.map((customer) => {
              const latest = latestHistory(customer)
              return (
                <article className={`history-customer-row ${customer.status === 'done' ? 'highlight-done' : ''}`} key={customer.id} onClick={() => setHistoryCustomerId(customer.id)}>
                  <div>
                    <strong>{customer.name}</strong>
                    <span>{customer.region} · {customer.phoneNumber || '연락처 없음'}</span>
                    <small>{latest ? `${latest.title} · ${formatTime(latest.at)}` : '아직 터치 이력 없음'}</small>
                  </div>
                  <span className={`pill ${customer.status === 'done' ? 'green' : latest ? 'orange' : ''}`}>{customer.status === 'done' ? '완료' : latest ? '진행중' : '미터치'}</span>
                </article>
              )
            })}
          </div>
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
                <strong>{template.title}</strong>
                <span>{template.body}</span>
              </article>
            ))}
          </div>
          <input value={newTemplateTitle} onChange={(event) => setNewTemplateTitle(event.target.value)} placeholder="템플릿 제목" />
          <textarea value={newTemplateBody} onChange={(event) => setNewTemplateBody(event.target.value)} placeholder="안녕하세요, {고객명}님." />
          <button className="primary full" type="button" onClick={addTemplate}><Plus size={18} /> 템플릿 추가</button>
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

  function renderMap(list: Customer[]) {
    const mapList = list.filter(hasTrustedCoordinates)
    const selected = selectedCustomer ?? mapList[0]
    const path = mapList.map((customer) => [customer.latitude!, customer.longitude!] as [number, number])
    return (
      <>
        <section className="panel">
          <PanelTitle title="오늘 지도" meta="완료 고객 제외" />
          <div className="map-frame">
            <button className="map-overlay-location" type="button" onClick={requestLocation}>
              <Navigation size={18} />
              내 위치
            </button>
            <MapContainer center={selected?.latitude && selected?.longitude ? [selected.latitude, selected.longitude] : location} zoom={13} scrollWheelZoom={false}>
              <MapFocus location={location} tick={mapFocusTick} />
              <TileLayer attribution="&copy; OpenStreetMap" url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
              {hasUserLocation && (
                <Marker position={location} icon={userLocationIcon}>
                  <Popup>내 위치</Popup>
                </Marker>
              )}
              {path.length > 1 && <Polyline positions={path} pathOptions={{ color: '#1f6feb', weight: 4, dashArray: '8 8' }} />}
              {mapList.map((customer, index) => (
                <CircleMarker
                  key={customer.id}
                  center={[customer.latitude!, customer.longitude!]}
                  radius={customer.id === selectedCustomerId ? 14 : 11}
                  eventHandlers={{ click: () => setSelectedCustomerId(customer.id) }}
                  pathOptions={{ color: '#162032', fillColor: customer.id === selectedCustomerId ? '#1f6feb' : '#162032', fillOpacity: 0.9 }}
                >
                  <Popup>{index + 1}. {customer.name}</Popup>
                </CircleMarker>
              ))}
            </MapContainer>
          </div>
        </section>
        {selected && <HeroCustomer customer={selected} badge="지도 선택" />}
      </>
    )
  }

  function renderRegionGroups() {
    const groups = remainingCustomers.reduce<Record<string, Customer[]>>((acc, customer) => {
      const key = customer.region ?? '지역 미확인'
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

  function HeroCustomer({ customer, badge }: { customer: Customer; badge: string }) {
    return (
      <article className={`hero-card ${customer.status === 'done' ? 'is-done' : ''}`}>
        <div className="chip-row">
          <span className="pill blue">{badge}</span>
          <span className="pill">{customer.region}</span>
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
          <span>{customer.region} · {customerDistanceLabel(customer)}</span>
          <small>{customer.address}</small>
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
        {customer.status === 'done' && <button className="secondary full" type="button" onClick={() => void reopenCustomer(customer)}><RotateCcw size={18} /> 완료취소</button>}
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

function TabButton({ active, icon, label, onClick }: { active: boolean; icon: React.ReactNode; label: string; onClick: () => void }) {
  return (
    <button className={active ? 'active' : ''} type="button" onClick={onClick}>
      {icon}
      <span>{label}</span>
    </button>
  )
}

function Metric({ value, label }: { value: number; label: string }) {
  return (
    <article className="metric">
      <strong>{value}</strong>
      <span>{label}</span>
    </article>
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
