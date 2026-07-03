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
  PhoneCall,
  Plus,
  Route,
  Search,
  Settings,
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

type ParsedCsv = {
  headers: string[]
  rows: string[][]
  mapping: FieldMapping
}

type FieldKey = 'name' | 'phoneNumber' | 'address' | 'notes'
type FieldMapping = Record<FieldKey, number | null>

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

const sampleScheduleItems: VisitScheduleItem[] = [
  makeScheduleItem('si-1', 'schedule-a', 'list-a', 'c-1', 1),
  makeScheduleItem('si-2', 'schedule-a', 'list-a', 'c-2', 2),
  makeScheduleItem('si-3', 'schedule-a', 'list-a', 'c-4', 3),
  makeScheduleItem('si-4', 'schedule-b', 'list-b', 'c-6', 1),
  makeScheduleItem('si-5', 'schedule-b', 'list-b', 'c-7', 2),
]

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
  return { id, customerListId, name, phoneNumber, address, notes, latitude, longitude, region, status, createdAt: now, updatedAt: now }
}

function makeSchedule(id: string, customerListId: string, title: string): VisitSchedule {
  const now = new Date().toISOString()
  return { id, customerListId, title, date: todayKey(), createdAt: now, updatedAt: now }
}

function makeScheduleItem(id: string, scheduleId: string, customerListId: string, customerId: string, orderIndex: number): VisitScheduleItem {
  return { id, scheduleId, customerListId, customerId, orderIndex, status: 'pending' }
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
  const mapping: FieldMapping = { name: null, phoneNumber: null, address: null, notes: null }
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

function extractRegion(address: string) {
  const parts = address.split(/\s+/).filter(Boolean)
  if (parts.length >= 3) return `${parts[1]} ${parts[2]}`
  if (parts.length >= 2) return parts.slice(0, 2).join(' ')
  return '지역 미확인'
}

function coordinateFromAddress(address: string, index: number): [number, number] {
  let hash = 0
  for (let i = 0; i < address.length; i += 1) {
    hash = (hash * 31 + address.charCodeAt(i)) % 10000
  }
  const lat = 37.49 + ((hash % 80) / 1000) + index * 0.0007
  const lng = 126.91 + (((hash / 80) % 130) / 1000) + index * 0.0005
  return [Number(lat.toFixed(6)), Number(lng.toFixed(6))]
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

  useEffect(() => {
    async function seedAndLoadInitialData() {
      const count = await appDb.customerLists.count()
      if (count === 0) {
        await appDb.transaction('rw', [appDb.customerLists, appDb.customers, appDb.visitSchedules, appDb.visitScheduleItems, appDb.visitLogs, appDb.messageTemplates], async () => {
          await appDb.customerLists.bulkAdd(sampleLists)
          await appDb.customers.bulkAdd(sampleCustomers)
          await appDb.visitSchedules.bulkAdd(sampleSchedules)
          await appDb.visitScheduleItems.bulkAdd(sampleScheduleItems)
          await appDb.visitLogs.bulkAdd(sampleVisitLogs)
          await appDb.messageTemplates.bulkAdd(defaultTemplates)
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
    if (!toast) return
    const timer = window.setTimeout(() => setToast(''), 3000)
    return () => window.clearTimeout(timer)
  }, [toast])

  useEffect(() => {
    if (activeListId) {
      localStorage.setItem('activeListId', activeListId)
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
    if (!activeListId && nextLists[0]) setActiveListId(nextLists[0].id)
  }

  function customerDistance(customer: Customer) {
    if (!customer.latitude || !customer.longitude) return Number.MAX_SAFE_INTEGER
    return distanceKm(location, [customer.latitude, customer.longitude])
  }

  function showToast(message: string) {
    setToast(message)
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
    await appDb.transaction('rw', appDb.customers, appDb.visitLogs, appDb.visitScheduleItems, async () => {
      await appDb.customers.update(customer.id, { status: 'done', updatedAt: now })
      await appDb.visitLogs.add({
        id: makeId('visit'),
        customerListId: customer.customerListId,
        customerId: customer.id,
        visitedAt: now,
        result: 'completed',
        memo: '',
        createdAt: now,
      })
      if (item) {
        await appDb.visitScheduleItems.update(item.id, { status: 'completed', completedAt: now })
      }
    })
    await refresh()
    showToast(`${customer.name} 방문완료가 저장되었습니다`)
  }

  async function sendManualSms(customer: Customer) {
    const now = new Date().toISOString()
    await appDb.contactLogs.add({
      id: makeId('contact'),
      customerListId: customer.customerListId,
      customerId: customer.id,
      type: 'manualSms',
      result: 'opened',
      createdAt: now,
    })
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
    const now = new Date().toISOString()
    await appDb.contactLogs.add({
      id: makeId('contact'),
      customerListId: customer.customerListId,
      customerId: customer.id,
      type: 'templateSms',
      templateId: template.id,
      messageBody: body,
      result: 'sentByUser',
      createdAt: now,
    })
    await refresh()
    window.location.href = `sms:${cleanPhone(customer.phoneNumber)}`
  }

  function callCustomer(customer: Customer) {
    window.location.href = `tel:${cleanPhone(customer.phoneNumber)}`
  }

  function navigateCustomer(customer: Customer) {
    if (!customer.latitude || !customer.longitude) {
      const destination = customer.address || customer.name
      window.location.href = `https://maps.apple.com/?q=${encodeURIComponent(destination)}`
      return
    }
    openTmapRoute(customer)
  }

  function openTmapRoute(customer: Customer) {
    const goalName = encodeURIComponent(customer.name || customer.address)
    const goalX = customer.longitude
    const goalY = customer.latitude
    const tmapUrl = `tmap://route?goalname=${goalName}&goalx=${goalX}&goaly=${goalY}&by=CAR&reqCoordType=WGS84&resCoordType=WGS84`
    const fallbackUrl = `https://maps.apple.com/?daddr=${goalY},${goalX}&q=${goalName}&dirflg=d`
    let pageHidden = false

    const handleVisibility = () => {
      if (document.hidden) {
        pageHidden = true
      }
    }

    document.addEventListener('visibilitychange', handleVisibility, { once: true })
    window.location.href = tmapUrl
    window.setTimeout(() => {
      document.removeEventListener('visibilitychange', handleVisibility)
      if (!pageHidden && document.visibilityState === 'visible') {
        window.location.href = fallbackUrl
      }
    }, 1400)
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
      .map((row, index): Customer | null => {
        const name = getMappedValue(row, csv.mapping.name)
        const phoneNumber = getMappedValue(row, csv.mapping.phoneNumber)
        const address = getMappedValue(row, csv.mapping.address)
        const notes = getMappedValue(row, csv.mapping.notes)
        if (!name || (!phoneNumber && !address)) return null
        const [latitude, longitude] = address ? coordinateFromAddress(address, index) : [undefined, undefined]
        return {
          id: makeId('customer'),
          customerListId: listId,
          name,
          phoneNumber,
          address,
          notes,
          latitude,
          longitude,
          region: address ? extractRegion(address) : '주소 없음',
          status: address ? 'open' : 'needsGeocode',
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
    const items = nextCustomers.slice(0, 3).map((customer, index) => ({
      id: makeId('schedule-item'),
      scheduleId: schedule.id,
      customerListId: listId,
      customerId: customer.id,
      orderIndex: index + 1,
      status: 'pending' as const,
    }))
    await appDb.transaction('rw', appDb.customerLists, appDb.customers, appDb.visitSchedules, appDb.visitScheduleItems, async () => {
      await appDb.customerLists.add(list)
      await appDb.customers.bulkAdd(nextCustomers)
      await appDb.visitSchedules.add(schedule)
      if (items.length) await appDb.visitScheduleItems.bulkAdd(items)
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

  function renderListSummary(list: CustomerList) {
    const listCustomers = customers.filter((customer) => customer.customerListId === list.id)
    const open = listCustomers.filter((customer) => customer.status === 'open').length
    const visits = visitLogs.filter((log) => log.customerListId === list.id).length
    const messages = contactLogs.filter((log) => log.customerListId === list.id).length
    return { total: listCustomers.length, open, visits, messages }
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
      {toast && <div className="toast">{toast}</div>}
    </main>
  )

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
    const next = currentCustomer
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
          <Metric value={activeVisits.length} label="방문 로그" />
          <Metric value={activeContacts.length} label="문자 로그" />
        </section>

        {todayMode === 'region' && renderRegionGroups()}
        {todayMode === 'map' && renderMap(targetList)}
        {todayMode !== 'region' && todayMode !== 'map' && (
          <>
            {next ? <HeroCustomer customer={next} badge={todayMode === 'schedule' ? '오늘 스케줄' : '가까운 순'} /> : <EmptyState text="오늘 남은 고객이 없습니다." />}
            <section className="panel">
              <PanelTitle title={todayMode === 'schedule' ? '오늘 스케줄' : '남은 고객'} meta={`${targetList.length}명`} />
              <div className="list-stack">
                {targetList.slice(todayMode === 'schedule' ? 0 : 1).map((customer) => (
                  <CustomerRow key={customer.id} customer={customer} showAdd={false} />
                ))}
              </div>
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
                <button className={`list-card ${list.id === activeListId ? 'selected' : ''}`} key={list.id} type="button" onClick={() => setActiveListId(list.id)}>
                  <strong>{list.name}</strong>
                  <span>{list.companyName} · {list.sourceFileName}</span>
                  <small>총 {summary.total}명 · 미방문 {summary.open}명 · 방문 {summary.visits}건 · 문자 {summary.messages}건</small>
                </button>
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
                </div>
              )
            })}
          </div>
          <button className="secondary full" type="button" onClick={sortScheduleByDistance}>가까운 순 정렬</button>
        </section>

        <div className="segmented">
          <button className={listFilter === 'open' ? 'active' : ''} type="button" onClick={() => setListFilter('open')}>미방문</button>
          <button className={listFilter === 'done' ? 'active' : ''} type="button" onClick={() => setListFilter('done')}>완료</button>
          <button className={listFilter === 'all' ? 'active' : ''} type="button" onClick={() => setListFilter('all')}>전체</button>
        </div>

        <section className="panel">
          <PanelTitle title="고객 목록" meta={`${filtered.length}명`} />
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
    const logs = [
      ...activeVisits.map((log) => ({ id: log.id, kind: '방문완료', customerId: log.customerId, at: log.visitedAt, detail: log.result })),
      ...activeContacts.map((log) => ({ id: log.id, kind: log.type === 'manualSms' ? '사용자 문자' : '템플릿 문자', customerId: log.customerId, at: log.createdAt, detail: log.result })),
    ].sort((a, b) => new Date(b.at).getTime() - new Date(a.at).getTime())
    return (
      <>
        <section className="metric-grid">
          <Metric value={activeVisits.length} label="방문 로그" />
          <Metric value={activeContacts.length} label="문자 로그" />
          <Metric value={pendingScheduleCustomers.length} label="스케줄 남음" />
        </section>
        <section className="panel">
          <PanelTitle title="활동 기록" meta={activeList?.name ?? ''} />
          <div className="list-stack">
            {logs.map((log) => {
              const customer = customers.find((entry) => entry.id === log.customerId)
              return (
                <article className="log-row" key={log.id}>
                  <div>
                    <strong>{customer?.name ?? '고객 없음'}</strong>
                    <span>{customer?.region} · 고객ID {log.customerId}</span>
                    <small>{formatTime(log.at)} · 결과: {log.detail}</small>
                  </div>
                  <span className={log.kind === '방문완료' ? 'pill green' : 'pill orange'}>{log.kind}</span>
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
    const mapList = list.filter((customer) => customer.latitude && customer.longitude)
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
      <article className="hero-card">
        <div className="chip-row">
          <span className="pill blue">{badge}</span>
          <span className="pill">{customer.region}</span>
          <span className="pill green">약 {customerDistance(customer).toFixed(1)}km</span>
        </div>
        <div>
          <h2>{customer.name}</h2>
          <p>{customer.address}</p>
          <small>{customer.notes}</small>
        </div>
        <ActionGrid customer={customer} />
        <button className="complete full" type="button" onClick={() => completeVisit(customer)}><Check size={22} /> 방문완료</button>
      </article>
    )
  }

  function CustomerRow({ customer, showAdd }: { customer: Customer; showAdd: boolean }) {
    return (
      <article className="customer-row" onClick={() => setSelectedCustomerId(customer.id)}>
        <div>
          <strong>{customer.name}</strong>
          <span>{customer.region} · 약 {customerDistance(customer).toFixed(1)}km</span>
          <small>{customer.address}</small>
        </div>
        <span className={`pill ${customer.status === 'done' ? 'green' : customer.status === 'hold' ? 'orange' : 'blue'}`}>{statusLabel(customer.status)}</span>
        <ActionGrid customer={customer} />
        {showAdd && customer.status === 'open' && <button className="secondary full" type="button" onClick={() => addSelectedToSchedule(customer)}>스케줄 추가</button>}
      </article>
    )
  }

  function ActionGrid({ customer }: { customer: Customer }) {
    return (
      <div className="action-grid">
        <button type="button" onClick={() => callCustomer(customer)}><PhoneCall size={18} /> 전화</button>
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
  }
  return labels[field]
}

function statusLabel(status: Customer['status']) {
  const labels: Record<Customer['status'], string> = {
    open: '미방문',
    done: '완료',
    hold: '보류',
    needsGeocode: '좌표확인',
  }
  return labels[status]
}

export default App
