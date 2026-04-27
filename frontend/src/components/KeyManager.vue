<script setup>
import { ref, computed } from 'vue'
import { useMessage, useDialog } from 'naive-ui'
import {
  KeyOutline, RefreshOutline, CopyOutline, TrashOutline, ShieldCheckmarkOutline,
  SaveOutline, CreateOutline, CheckmarkOutline, CloseOutline,
} from '@vicons/ionicons5'
import { keys, addKey, removeKey, renameKey, findByHex } from '../stores/keyStore'

const message = useMessage()
const dialog  = useDialog()

// ── Wails 容错导入 ──
let GenerateKey = async () => { throw new Error('后端未就绪') }
;(async () => {
  try { ({ GenerateKey } = await import('../../wailsjs/go/main/App')) } catch {}
})()

// ── 状态 ──
const currentKey  = ref('')
const currentName = ref('')
const generating  = ref(false)
const editingId   = ref('')
const editingName = ref('')

// 分4段展示
const keySegments = computed(() => {
  if (!currentKey.value || currentKey.value.length !== 32) return []
  return [
    currentKey.value.slice(0, 8),
    currentKey.value.slice(8, 16),
    currentKey.value.slice(16, 24),
    currentKey.value.slice(24, 32),
  ]
})

const currentInLib = computed(() => !!findByHex(currentKey.value))

async function handleGenerateKey() {
  generating.value = true
  try {
    const k = await GenerateKey()
    currentKey.value = k
  } catch {
    const bytes = new Uint8Array(16)
    crypto.getRandomValues(bytes)
    currentKey.value = Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('')
  } finally {
    generating.value = false
    currentName.value = ''
  }
}

function copyKey() {
  if (!currentKey.value) return
  navigator.clipboard?.writeText(currentKey.value)
  message.success('密钥已复制到剪贴板')
}

function copyHex(hex) {
  navigator.clipboard?.writeText(hex)
  message.success('密钥已复制')
}

function clearKey() {
  currentKey.value = ''
  currentName.value = ''
}

function saveCurrentToLib() {
  if (!currentKey.value) return
  if (!/^[0-9a-fA-F]{32}$/.test(currentKey.value)) {
    message.error('密钥格式无效，应为 32 位十六进制')
    return
  }
  const exist = findByHex(currentKey.value)
  if (exist) {
    message.info(`该密钥已在库中：${exist.name}`)
    return
  }
  const item = addKey(currentKey.value, currentName.value)
  if (item) {
    message.success(`已保存到密钥库：${item.name}`)
    currentName.value = ''
  }
}

function useLibKey(item) {
  currentKey.value = item.hex
  currentName.value = item.name
  message.info('已载入密钥')
}

function startRename(item) {
  editingId.value = item.id
  editingName.value = item.name
}

function commitRename() {
  if (editingId.value) {
    renameKey(editingId.value, editingName.value)
    message.success('已重命名')
  }
  editingId.value = ''
  editingName.value = ''
}

function cancelRename() {
  editingId.value = ''
  editingName.value = ''
}

function confirmDelete(item) {
  dialog.warning({
    title: '删除密钥',
    content: `确定删除「${item.name}」？删除后无法用此密钥解密之前加密的文件。`,
    positiveText: '删除',
    negativeText: '取消',
    onPositiveClick: () => {
      removeKey(item.id)
      message.success('已删除')
    }
  })
}

function formatTime(ts) {
  const d = new Date(ts)
  const pad = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}
</script>

<template>
  <n-card :bordered="false" size="large">
    <template #header>
      <div class="panel-header">
        <n-icon :component="KeyOutline" :size="20" class="panel-icon-key" />
        <span>密钥管理</span>
      </div>
    </template>

    <n-space vertical :size="20">

      <!-- 说明 Alert -->
      <n-alert type="warning" :show-icon="true" class="info-alert">
        SM4 密钥固定为 128 bit（16 字节）。这里以十六进制展示。生成后保存到密钥库，可在加密 / 解密页面下拉选择。
      </n-alert>

      <!-- 密钥大展示区 -->
      <div class="key-display" :class="{ 'key-display-empty': !currentKey }">
        <template v-if="keySegments.length">
          <div class="key-segments">
            <span
              v-for="(seg, i) in keySegments"
              :key="i"
              class="key-seg"
            >{{ seg }}</span>
          </div>
          <div class="key-bits-label">128 bit · 32 hex chars</div>
        </template>
        <template v-else>
          <n-icon :component="KeyOutline" :size="36" class="key-empty-icon" />
          <div class="key-empty-hint">尚未生成密钥</div>
          <div class="key-empty-sub">点击下方按钮随机生成</div>
        </template>
      </div>

      <!-- 密钥强度 -->
      <div v-if="currentKey" class="strength-section">
        <div class="strength-header">
          <div class="strength-label">
            <n-icon :component="ShieldCheckmarkOutline" :size="14" class="strength-icon" />
            <span>密钥强度</span>
          </div>
          <span class="strength-value">足够强壮</span>
        </div>
        <n-progress
          type="line"
          :percentage="100"
          :height="8"
          :border-radius="4"
          color="#18a058"
          :show-indicator="false"
        />
        <div class="strength-info">128 bit 随机熵 — 符合 GM/T 0002-2012 规范</div>
      </div>

      <!-- 操作按钮 -->
      <div class="key-btns">
        <n-button
          type="primary"
          :loading="generating"
          @click="handleGenerateKey"
          class="generate-btn"
        >
          <template #icon>
            <n-icon :component="RefreshOutline" />
          </template>
          随机生成
        </n-button>
        <n-button
          :disabled="!currentKey"
          @click="copyKey"
        >
          <template #icon>
            <n-icon :component="CopyOutline" />
          </template>
          复制
        </n-button>
        <n-button
          :disabled="!currentKey"
          @click="clearKey"
          type="error"
          secondary
        >
          <template #icon>
            <n-icon :component="TrashOutline" />
          </template>
          清空
        </n-button>
      </div>

      <!-- 保存到密钥库 -->
      <div v-if="currentKey" class="save-row">
        <n-input
          v-model:value="currentName"
          placeholder="为该密钥起个名字（可选）"
          :disabled="currentInLib"
          class="save-name-input"
        />
        <n-button
          type="info"
          :disabled="currentInLib"
          @click="saveCurrentToLib"
        >
          <template #icon>
            <n-icon :component="SaveOutline" />
          </template>
          {{ currentInLib ? '已在库中' : '保存到密钥库' }}
        </n-button>
      </div>

      <!-- 密钥库 -->
      <n-divider title-placement="left">
        <span class="divider-title">密钥库（{{ keys.length }}）</span>
      </n-divider>

      <div v-if="!keys.length" class="empty-lib">
        <n-icon :component="KeyOutline" :size="28" class="empty-icon" />
        <div class="empty-text">暂无已保存密钥</div>
        <div class="empty-sub">生成密钥后点击「保存到密钥库」</div>
      </div>

      <div v-else class="lib-list">
        <div
          v-for="item in keys"
          :key="item.id"
          class="lib-item"
          :class="{ 'lib-current': item.hex === currentKey }"
        >
          <div class="lib-head">
            <template v-if="editingId === item.id">
              <n-input
                v-model:value="editingName"
                size="small"
                class="rename-input"
                @keydown.enter="commitRename"
                @keydown.esc="cancelRename"
                autofocus
              />
              <n-button text size="small" @click="commitRename">
                <template #icon><n-icon :component="CheckmarkOutline" /></template>
              </n-button>
              <n-button text size="small" @click="cancelRename">
                <template #icon><n-icon :component="CloseOutline" /></template>
              </n-button>
            </template>
            <template v-else>
              <span class="lib-name">{{ item.name }}</span>
              <n-button text size="tiny" @click="startRename(item)" class="lib-rename">
                <template #icon><n-icon :component="CreateOutline" :size="13" /></template>
              </n-button>
            </template>
            <span class="lib-time">{{ formatTime(item.createdAt) }}</span>
          </div>
          <div class="lib-hex">{{ item.hex }}</div>
          <div class="lib-actions">
            <n-button
              text
              size="tiny"
              @click="useLibKey(item)"
              :disabled="item.hex === currentKey"
            >使用</n-button>
            <n-button text size="tiny" @click="copyHex(item.hex)">复制</n-button>
            <n-button text size="tiny" type="error" @click="confirmDelete(item)">删除</n-button>
          </div>
        </div>
      </div>

      <n-text depth="3" style="font-size: 12px">
        提示：密钥保存在浏览器本地存储中（localStorage）。生产环境建议结合系统钥匙串或 PBKDF2 密码派生。
      </n-text>

    </n-space>
  </n-card>
</template>

<style scoped>
.panel-header {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 15px;
  font-weight: 600;
}

.panel-icon-key { color: #f0a020; }
.info-alert { border-radius: 10px !important; }

/* ── 密钥展示区 ── */
.key-display {
  border-radius: 14px;
  padding: 24px;
  text-align: center;
  min-height: 110px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 10px;
  border: 1px solid rgba(240, 160, 32, 0.3);
  background: rgba(240, 160, 32, 0.04);
  transition: background 0.2s ease;
}

.key-display-empty {
  border-style: dashed;
  border-color: rgba(128, 128, 128, 0.2);
  background: transparent;
}

.key-segments {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
  justify-content: center;
}

.key-seg {
  font-family: 'SF Mono', 'Fira Mono', 'Cascadia Code', 'Consolas', monospace;
  font-size: 18px;
  font-weight: 600;
  letter-spacing: 0.06em;
  padding: 4px 10px;
  border-radius: 8px;
  background: rgba(240, 160, 32, 0.1);
  color: #f0a020;
}

.key-bits-label {
  font-size: 11px;
  color: rgba(128, 128, 128, 0.5);
  letter-spacing: 0.04em;
}

.key-empty-icon { color: rgba(128, 128, 128, 0.25); }
.key-empty-hint { font-size: 14px; color: rgba(128, 128, 128, 0.6); }
.key-empty-sub  { font-size: 12px; color: rgba(128, 128, 128, 0.4); }

/* ── 强度 ── */
.strength-section { display: flex; flex-direction: column; gap: 6px; }

.strength-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.strength-label {
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 12px;
  color: rgba(128, 128, 128, 0.75);
}

.strength-icon { color: #18a058; }

.strength-value {
  font-size: 12px;
  font-weight: 600;
  color: #18a058;
}

.strength-info {
  font-size: 11px;
  color: rgba(128, 128, 128, 0.5);
}

/* ── 按钮组 ── */
.key-btns {
  display: flex;
  gap: 8px;
}

.generate-btn { flex: 1; }

/* ── 保存到库 ── */
.save-row {
  display: flex;
  gap: 8px;
  align-items: center;
}

.save-name-input { flex: 1; }

/* ── 密钥库 ── */
.divider-title { font-size: 12px; color: rgba(128, 128, 128, 0.6); }

.empty-lib {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  padding: 24px 12px;
  border: 1px dashed rgba(128, 128, 128, 0.2);
  border-radius: 12px;
}

.empty-icon { color: rgba(128, 128, 128, 0.3); }
.empty-text { font-size: 13px; color: rgba(128, 128, 128, 0.65); }
.empty-sub  { font-size: 11px; color: rgba(128, 128, 128, 0.45); }

.lib-list { display: flex; flex-direction: column; gap: 8px; }

.lib-item {
  border-radius: 10px;
  border: 1px solid rgba(128, 128, 128, 0.15);
  padding: 12px 14px;
  display: flex;
  flex-direction: column;
  gap: 6px;
  transition: background 0.15s ease, border-color 0.15s ease;
}

.lib-item:hover { background: rgba(128, 128, 128, 0.04); }

.lib-current {
  border-color: rgba(240, 160, 32, 0.4);
  background: rgba(240, 160, 32, 0.05);
}

.lib-head {
  display: flex;
  align-items: center;
  gap: 6px;
}

.lib-name {
  font-size: 13px;
  font-weight: 600;
  color: rgba(128, 128, 128, 0.95);
  flex-shrink: 0;
}

.lib-rename { opacity: 0.5; }
.lib-rename:hover { opacity: 1; }

.rename-input { max-width: 200px; }

.lib-time {
  font-size: 11px;
  color: rgba(128, 128, 128, 0.5);
  margin-left: auto;
}

.lib-hex {
  font-family: 'SF Mono', 'Fira Mono', 'Cascadia Code', 'Consolas', monospace;
  font-size: 12.5px;
  letter-spacing: 0.04em;
  color: rgba(128, 128, 128, 0.85);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.lib-actions {
  display: flex;
  gap: 12px;
}
</style>
