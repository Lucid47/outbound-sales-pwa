import Dexie, { type EntityTable } from 'dexie'

export type CustomerStatus = 'open' | 'done' | 'hold' | 'needsGeocode'
export type ScheduleItemStatus = 'pending' | 'completed' | 'skipped' | 'hold'
export type ContactLogType = 'call' | 'manualSms' | 'templateSms' | 'note' | 'statusComplete' | 'statusReopen'

export interface CustomerList {
  id: string
  name: string
  companyName: string
  sourceFileName: string
  importedAt: string
  createdAt: string
  updatedAt: string
}

export interface Customer {
  id: string
  customerListId: string
  name: string
  phoneNumber: string
  address: string
  notes: string
  latitude?: number
  longitude?: number
  coordinateSource?: 'sample' | 'csv' | 'geocoded'
  geocodedAt?: string
  geocodeQuery?: string
  region?: string
  status: CustomerStatus
  createdAt: string
  updatedAt: string
}

export interface VisitLog {
  id: string
  customerListId: string
  customerId: string
  visitedAt: string
  result: 'completed'
  memo?: string
  createdAt: string
}

export interface ContactLog {
  id: string
  customerListId: string
  customerId: string
  type: ContactLogType
  templateId?: string
  messageBody?: string
  result: 'opened' | 'sentByUser' | 'completed' | 'reopened' | 'saved' | 'cancelled' | 'unknown'
  createdAt: string
}

export interface VisitSchedule {
  id: string
  customerListId: string
  date: string
  title: string
  createdAt: string
  updatedAt: string
}

export interface VisitScheduleItem {
  id: string
  scheduleId: string
  customerListId: string
  customerId: string
  orderIndex: number
  status: ScheduleItemStatus
  completedAt?: string
}

export interface MessageTemplate {
  id: string
  title: string
  body: string
  isDefault: boolean
  createdAt: string
  updatedAt: string
}

export const appDb = new Dexie('outboundSalesDb') as Dexie & {
  customerLists: EntityTable<CustomerList, 'id'>
  customers: EntityTable<Customer, 'id'>
  visitLogs: EntityTable<VisitLog, 'id'>
  contactLogs: EntityTable<ContactLog, 'id'>
  visitSchedules: EntityTable<VisitSchedule, 'id'>
  visitScheduleItems: EntityTable<VisitScheduleItem, 'id'>
  messageTemplates: EntityTable<MessageTemplate, 'id'>
}

appDb.version(1).stores({
  customerLists: 'id, name, companyName, importedAt',
  customers: 'id, customerListId, name, phoneNumber, status, region',
  visitLogs: 'id, customerListId, customerId, visitedAt, result',
  contactLogs: 'id, customerListId, customerId, type, createdAt, result',
  visitSchedules: 'id, customerListId, date',
  visitScheduleItems: 'id, scheduleId, customerListId, customerId, orderIndex, status',
  messageTemplates: 'id, title, isDefault',
})
