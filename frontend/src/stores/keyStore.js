import { ref, watch } from 'vue'

const STORAGE_KEY = 'bittern.keyStore.v1'

function loadFromStorage() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return []
    const parsed = JSON.parse(raw)
    if (!Array.isArray(parsed)) return []
    return parsed.filter(it => it && typeof it.hex === 'string' && /^[0-9a-fA-F]{32}$/.test(it.hex))
  } catch {
    return []
  }
}

function persist(list) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(list))
  } catch {}
}

// 单例响应式数组：所有组件共享同一份引用
export const keys = ref(loadFromStorage())

watch(keys, (val) => persist(val), { deep: true })

function genId() {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8)
}

function defaultName() {
  const d = new Date()
  const pad = (n) => String(n).padStart(2, '0')
  return `密钥 ${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
}

export function addKey(hex, name) {
  if (!hex || !/^[0-9a-fA-F]{32}$/.test(hex)) return null
  const lower = hex.toLowerCase()
  const exist = keys.value.find(k => k.hex.toLowerCase() === lower)
  if (exist) return exist
  const item = {
    id: genId(),
    name: (name && name.trim()) || defaultName(),
    hex: lower,
    createdAt: Date.now(),
  }
  keys.value = [item, ...keys.value]
  return item
}

export function removeKey(id) {
  keys.value = keys.value.filter(k => k.id !== id)
}

export function renameKey(id, name) {
  const idx = keys.value.findIndex(k => k.id === id)
  if (idx < 0) return
  keys.value[idx] = { ...keys.value[idx], name: name.trim() || keys.value[idx].name }
}

export function clearAll() {
  keys.value = []
}

export function findByHex(hex) {
  if (!hex) return null
  const lower = hex.toLowerCase()
  return keys.value.find(k => k.hex.toLowerCase() === lower) || null
}
