<script setup>
import { ref, computed } from 'vue'
import { useMessage } from 'naive-ui'
import {
  KeyOutline, RefreshOutline, CopyOutline, TrashOutline, ShieldCheckmarkOutline,
} from '@vicons/ionicons5'

const message = useMessage()

// ── Wails 容错导入 ──
let GenerateKey = async () => { throw new Error('后端未就绪') }
;(async () => {
  try { ({ GenerateKey } = await import('../../wailsjs/go/main/App')) } catch {}
})()

// ── 状态 ──
const currentKey  = ref('')
const history     = ref([])    // [{ hex, time }]
const generating  = ref(false)

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
    // 保存历史（最多5条）
    history.value.unshift({ hex: currentKey.value, time: new Date().toLocaleTimeString() })
    if (history.value.length > 5) history.value.pop()
  }
}

function copyKey() {
  if (!currentKey.value) return
  navigator.clipboard?.writeText(currentKey.value)
  message.success('密钥已复制到剪贴板')
}

function copyHistoryKey(hex) {
  navigator.clipboard?.writeText(hex)
  message.success('历史密钥已复制')
}

function clearKey() {
  currentKey.value = ''
}

function useHistoryKey(hex) {
  currentKey.value = hex
  message.info('已载入历史密钥')
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
        SM4 密钥固定为 128 bit（16 字节）。这里以十六进制展示，方便复制粘贴。
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

      <!-- 历史记录 -->
      <template v-if="history.length">
        <n-divider title-placement="left">
          <span class="divider-title">本次会话历史（最近 {{ history.length }} 条）</span>
        </n-divider>
        <div class="history-list">
          <div
            v-for="(item, i) in history"
            :key="i"
            class="history-item"
            :class="{ 'history-current': item.hex === currentKey }"
          >
            <div class="history-hex">{{ item.hex }}</div>
            <div class="history-meta">
              <span class="history-time">{{ item.time }}</span>
              <div class="history-actions">
                <n-button
                  text
                  size="tiny"
                  @click="useHistoryKey(item.hex)"
                  :disabled="item.hex === currentKey"
                >使用</n-button>
                <n-button text size="tiny" @click="copyHistoryKey(item.hex)">复制</n-button>
              </div>
            </div>
          </div>
        </div>
      </template>

      <n-text depth="3" style="font-size: 12px">
        提示：实际项目中可使用密码 + 盐 (PBKDF2) 派生密钥，避免直接保存明文密钥。
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

/* ── 历史记录 ── */
.divider-title { font-size: 12px; color: rgba(128, 128, 128, 0.6); }

.history-list { display: flex; flex-direction: column; gap: 6px; }

.history-item {
  border-radius: 10px;
  border: 1px solid rgba(128, 128, 128, 0.15);
  padding: 10px 14px;
  display: flex;
  flex-direction: column;
  gap: 4px;
  transition: background 0.15s ease;
}

.history-item:hover { background: rgba(128, 128, 128, 0.04); }

.history-current {
  border-color: rgba(240, 160, 32, 0.35);
  background: rgba(240, 160, 32, 0.04);
}

.history-hex {
  font-family: 'SF Mono', 'Fira Mono', 'Cascadia Code', 'Consolas', monospace;
  font-size: 13px;
  letter-spacing: 0.04em;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.history-meta {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.history-time { font-size: 11px; color: rgba(128, 128, 128, 0.5); }
.history-actions { display: flex; gap: 8px; }
</style>
