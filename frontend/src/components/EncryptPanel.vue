<script setup>
import { ref, computed, onMounted, onUnmounted, h } from 'vue'
import { useMessage } from 'naive-ui'
import {
  DocumentOutline, KeyOutline, LockClosedOutline, FolderOpenOutline,
  RefreshOutline, CopyOutline, EyeOutline, EyeOffOutline, CheckmarkCircleOutline,
  CloudUploadOutline, LibraryOutline,
} from '@vicons/ionicons5'
import { keys, addKey, findByHex } from '../stores/keyStore'

const message = useMessage()

// ── Wails 方法容错导入 ──
let SelectInputFile  = async () => '/tmp/demo.txt'
let SelectOutputFile = async () => '/tmp/demo.txt.sm4'
let EncryptFile      = async () => { throw new Error('后端未就绪') }
let GenerateKey      = async () => { throw new Error('后端未就绪') }
let EventsOn         = () => {}
let EventsOff        = () => {}

;(async () => {
  try { ({ SelectInputFile, SelectOutputFile, EncryptFile, GenerateKey } = await import('../../wailsjs/go/main/App')) } catch {}
  try { ({ EventsOn, EventsOff } = await import('../../wailsjs/runtime/runtime')) } catch {}
})()

// ── 状态 ──
const inputFile  = ref('')
const inputSize  = ref(0)
const key        = ref('')
const showKey    = ref(false)
const mode       = ref('CBC')
const outputFile = ref('')
const progress   = ref(0)
const processedBytes = ref(0)
const running    = ref(false)
const done       = ref(false)
const dragging   = ref(false)

const inputFileName = computed(() => {
  if (!inputFile.value) return ''
  return inputFile.value.split(/[\\/]/).pop()
})

const fileSizeLabel = computed(() => {
  if (!inputSize.value) return ''
  if (inputSize.value < 1024) return `${inputSize.value} B`
  if (inputSize.value < 1024 * 1024) return `${(inputSize.value / 1024).toFixed(1)} KB`
  return `${(inputSize.value / 1024 / 1024).toFixed(2)} MB`
})

const progressLabel = computed(() => {
  if (!processedBytes.value) return `${progress.value}%`
  const mb = (processedBytes.value / 1024 / 1024).toFixed(2)
  return `${progress.value}% · ${mb} MB`
})

// ── 文件选择 ──
async function browseInput() {
  try {
    const path = await SelectInputFile()
    if (!path) return
    inputFile.value = path
    outputFile.value = path + '.sm4'
    done.value = false
    progress.value = 0
    processedBytes.value = 0
  } catch (e) {
    message.error('选择文件失败：' + e.message)
  }
}

async function browseOutput() {
  try {
    const path = await SelectOutputFile()
    if (path) outputFile.value = path
  } catch (e) {
    message.error('选择输出路径失败：' + e.message)
  }
}

function onDragOver() { dragging.value = true }
function onDragLeave() { dragging.value = false }
function onDrop() { dragging.value = false }

function setInputFromPath(path) {
  if (!path) return
  inputFile.value = path
  inputSize.value = 0
  outputFile.value = path + '.sm4'
  done.value = false
  progress.value = 0
  processedBytes.value = 0
}

// ── 密钥操作 ──
const selectedKeyId = ref(null)

const keyOptions = computed(() =>
  keys.value.map(k => ({
    label: k.name,
    value: k.id,
    hex: k.hex,
  }))
)

function renderKeyOption(option) {
  if (!option) return null
  return h('div', { style: 'display:flex;flex-direction:column;gap:2px;padding:2px 0;' }, [
    h('span', { style: 'font-size:13px;font-weight:600;' }, option.label),
    h('span', {
      style: 'font-family:monospace;font-size:11px;color:rgba(128,128,128,0.7);letter-spacing:0.04em;'
    }, option.hex),
  ])
}

function onSelectLibKey(id) {
  if (!id) return
  const item = keys.value.find(k => k.id === id)
  if (item) {
    key.value = item.hex
    message.info(`已载入密钥：${item.name}`)
  }
}

// 密钥手动编辑后，若与已选条目不再一致，清除选择
function onKeyInput() {
  if (!selectedKeyId.value) return
  const item = keys.value.find(k => k.id === selectedKeyId.value)
  if (!item || item.hex.toLowerCase() !== key.value.toLowerCase()) {
    selectedKeyId.value = null
  }
}

async function handleGenerateKey() {
  let hex
  try {
    hex = await GenerateKey()
  } catch {
    const bytes = new Uint8Array(16)
    crypto.getRandomValues(bytes)
    hex = Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('')
  }
  key.value = hex
  // 自动入库（默认按时间命名），方便解密时直接选到
  const item = addKey(hex)
  if (item) {
    selectedKeyId.value = item.id
    message.success(`已生成并保存到密钥库：${item.name}`)
  }
}

function copyKey() {
  if (!key.value) return
  navigator.clipboard?.writeText(key.value)
  message.success('密钥已复制到剪贴板')
}

function saveCurrentKey() {
  if (!key.value) {
    message.warning('请先输入或生成密钥')
    return
  }
  if (!/^[0-9a-fA-F]{32}$/.test(key.value)) {
    message.error('密钥格式无效，应为 32 位十六进制')
    return
  }
  const exist = findByHex(key.value)
  if (exist) {
    selectedKeyId.value = exist.id
    message.info(`该密钥已在库中：${exist.name}`)
    return
  }
  const item = addKey(key.value)
  if (item) {
    selectedKeyId.value = item.id
    message.success(`已保存到密钥库：${item.name}`)
  }
}

// ── 进度事件 + Wails 文件拖拽 ──
onMounted(() => {
  try {
    EventsOn('encrypt:progress', (data) => {
      progress.value = data.percent ?? 0
      processedBytes.value = data.bytes ?? 0
    })
  } catch {}
  if (window.runtime?.OnFileDrop) {
    window.runtime.OnFileDrop((x, y, paths) => {
      dragging.value = false
      if (paths && paths.length > 0) setInputFromPath(paths[0])
    }, true)
  }
})

onUnmounted(() => {
  try { EventsOff('encrypt:progress') } catch {}
  if (window.runtime?.OnFileDropOff) window.runtime.OnFileDropOff()
})

// ── 加密 ──
async function handleEncrypt() {
  if (!inputFile.value) { message.warning('请先选择输入文件'); return }
  if (!key.value)        { message.warning('请输入或生成密钥'); return }
  if (!outputFile.value) { message.warning('请指定输出文件路径'); return }

  running.value = true
  done.value    = false
  progress.value = 0
  processedBytes.value = 0

  try {
    await EncryptFile({
      inputPath: inputFile.value,
      outputPath: outputFile.value,
      keyHex: key.value,
      mode: mode.value
    })
    progress.value = 100
    done.value = true
    message.success('加密完成！')
  } catch (e) {
    message.error('加密失败：' + e.message)
  } finally {
    running.value = false
  }
}

const modeCards = [
  {
    value: 'CBC',
    label: 'CBC',
    desc: '密码分组链接模式，相同明文块输出不同密文',
    badge: '经典',
  },
  {
    value: 'CTR',
    label: 'CTR',
    desc: '计数器模式，可并行加解密、性能更高',
    badge: '高速',
  },
]
</script>

<template>
  <n-card :bordered="false" size="large" class="panel-card">
    <template #header>
      <div class="panel-header">
        <n-icon :component="LockClosedOutline" :size="20" class="panel-icon-encrypt" />
        <span>文件加密</span>
      </div>
    </template>

    <n-space vertical :size="20">

      <!-- 文件 Dropzone -->
      <div
        class="dropzone"
        style="--wails-drop-target: drop"
        :class="{ 'dz-dragging': dragging, 'dz-filled': inputFileName }"
        @click="browseInput"
        @dragover.prevent="onDragOver"
        @dragleave.prevent="onDragLeave"
        @drop.prevent="onDrop"
      >
        <template v-if="inputFileName">
          <n-icon :component="DocumentOutline" :size="32" class="dz-file-icon" />
          <div class="dz-filename">{{ inputFileName }}</div>
          <div class="dz-size" v-if="fileSizeLabel">{{ fileSizeLabel }}</div>
          <div class="dz-hint">点击重新选择</div>
        </template>
        <template v-else>
          <n-icon :component="CloudUploadOutline" :size="36" class="dz-upload-icon" />
          <div class="dz-title">拖拽文件到此处，或点击选择</div>
          <div class="dz-hint">支持任意类型文件</div>
        </template>
      </div>

      <!-- 密钥输入 -->
      <div class="field-group">
        <div class="field-label">
          <n-icon :component="KeyOutline" :size="14" />
          <span>SM4 密钥（128 bit / 16 字节）</span>
        </div>

        <!-- 密钥库下拉选择 -->
        <div class="key-row">
          <n-select
            v-model:value="selectedKeyId"
            :options="keyOptions"
            :render-label="renderKeyOption"
            :placeholder="keyOptions.length ? '从密钥库选择已保存的密钥…' : '密钥库暂无保存密钥'"
            :disabled="!keyOptions.length"
            clearable
            @update:value="onSelectLibKey"
            class="key-input"
          />
          <n-tooltip content="保存当前密钥到密钥库">
            <template #trigger>
              <button class="key-btn" @click="saveCurrentKey" :disabled="!key">
                <n-icon :component="LibraryOutline" :size="16" />
              </button>
            </template>
            保存到密钥库
          </n-tooltip>
        </div>

        <div class="key-row">
          <n-input
            v-model:value="key"
            :type="showKey ? 'text' : 'password'"
            placeholder="输入或随机生成 SM4 密钥"
            class="key-input"
            :input-props="{ style: 'font-family: monospace' }"
            @input="onKeyInput"
          />
          <div class="key-actions">
            <n-tooltip content="随机生成（自动入库）">
              <template #trigger>
                <button class="key-btn" @click="handleGenerateKey">
                  <n-icon :component="RefreshOutline" :size="16" />
                </button>
              </template>
              随机生成（自动入库）
            </n-tooltip>
            <n-tooltip>
              <template #trigger>
                <button class="key-btn" @click="showKey = !showKey">
                  <n-icon :component="showKey ? EyeOffOutline : EyeOutline" :size="16" />
                </button>
              </template>
              {{ showKey ? '隐藏' : '显示' }}密钥
            </n-tooltip>
            <n-tooltip content="复制密钥">
              <template #trigger>
                <button class="key-btn" @click="copyKey" :disabled="!key">
                  <n-icon :component="CopyOutline" :size="16" />
                </button>
              </template>
              复制密钥
            </n-tooltip>
          </div>
        </div>
      </div>

      <!-- 加密模式卡片选择 -->
      <div class="field-group">
        <div class="field-label">
          <n-icon :component="LockClosedOutline" :size="14" />
          <span>加密模式</span>
        </div>
        <div class="mode-cards">
          <div
            v-for="m in modeCards"
            :key="m.value"
            class="mode-card"
            :class="{ 'mode-card-active': mode === m.value }"
            @click="mode = m.value"
          >
            <div class="mode-card-top">
              <span class="mode-name">{{ m.label }}</span>
              <span v-if="m.badge" class="mode-badge">{{ m.badge }}</span>
            </div>
            <p class="mode-desc">{{ m.desc }}</p>
            <div class="mode-radio">
              <div class="mode-dot" :class="{ 'mode-dot-active': mode === m.value }" />
            </div>
          </div>
        </div>
      </div>

      <!-- 输出路径 -->
      <div class="field-group">
        <div class="field-label">
          <n-icon :component="FolderOpenOutline" :size="14" />
          <span>输出路径</span>
        </div>
        <div class="key-row">
          <n-input v-model:value="outputFile" placeholder="加密后文件保存位置…" />
          <button class="browse-btn" @click="browseOutput">浏览</button>
        </div>
      </div>

      <!-- 进度条 -->
      <Transition name="progress-fade">
        <div v-if="running || progress > 0" class="progress-wrap">
          <div class="progress-header">
            <span>{{ running ? '加密中…' : (done ? '完成' : '就绪') }}</span>
            <span class="progress-pct">{{ progressLabel }}</span>
          </div>
          <n-progress
            type="line"
            :percentage="progress"
            :height="10"
            :border-radius="5"
            :color="done ? '#18a058' : undefined"
          />
        </div>
      </Transition>

      <!-- 成功 Alert -->
      <Transition name="progress-fade">
        <n-alert
          v-if="done"
          type="success"
          :show-icon="true"
          :title="'加密成功'"
        >
          <template #default>
            文件已保存至：<code style="word-break: break-all">{{ outputFile }}</code>
          </template>
          <template #action>
            <n-button size="small" @click="done = false">关闭</n-button>
          </template>
        </n-alert>
      </Transition>

      <!-- 操作按钮 -->
      <n-space justify="end">
        <n-button
          type="primary"
          size="large"
          :loading="running"
          :disabled="running"
          @click="handleEncrypt"
          class="action-btn"
        >
          <template #icon>
            <n-icon :component="running ? undefined : LockClosedOutline" />
          </template>
          {{ running ? '加密中…' : '开始加密' }}
        </n-button>
      </n-space>

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

.panel-icon-encrypt { color: #7c6cf0; }

/* ── Dropzone ── */
.dropzone {
  border: 2px dashed rgba(124, 108, 240, 0.4);
  border-radius: 14px;
  padding: 28px 24px;
  text-align: center;
  cursor: pointer;
  transition: border-color 0.2s ease, background 0.2s ease, transform 0.15s ease;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
}

.dropzone:hover, .dz-dragging {
  border-color: rgba(124, 108, 240, 0.75);
  background: rgba(124, 108, 240, 0.06);
  transform: scale(1.005);
}

.dz-filled {
  border-style: solid;
  border-color: rgba(124, 108, 240, 0.5);
  background: rgba(124, 108, 240, 0.04);
}

.dz-upload-icon { color: rgba(124, 108, 240, 0.5); }
.dz-file-icon   { color: #7c6cf0; }

.dz-title {
  font-size: 14px;
  color: rgba(128, 128, 128, 0.8);
  margin-top: 4px;
}

.dz-filename {
  font-size: 14px;
  font-weight: 600;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.dz-size {
  font-size: 12px;
  color: rgba(128, 128, 128, 0.7);
}

.dz-hint {
  font-size: 11px;
  color: rgba(128, 128, 128, 0.5);
}

/* ── 字段组 ── */
.field-group { display: flex; flex-direction: column; gap: 8px; }

.field-label {
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 12px;
  font-weight: 500;
  color: rgba(128, 128, 128, 0.85);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

/* ── 密钥行 ── */
.key-row {
  display: flex;
  gap: 8px;
  align-items: center;
}

.key-input { flex: 1; }

.key-actions {
  display: flex;
  gap: 4px;
}

.key-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  border-radius: 8px;
  border: 1px solid rgba(128, 128, 128, 0.2);
  cursor: pointer;
  background: transparent;
  color: rgba(128, 128, 128, 0.7);
  transition: background 0.15s ease, transform 0.12s ease, color 0.15s ease;
}

.key-btn:hover:not(:disabled) {
  background: rgba(124, 108, 240, 0.12);
  color: #7c6cf0;
  transform: scale(1.05);
}

.key-btn:active:not(:disabled) { transform: scale(0.95); }
.key-btn:disabled { opacity: 0.35; cursor: not-allowed; }

/* ── 模式卡片 ── */
.mode-cards {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
}

.mode-card {
  position: relative;
  border: 1px solid rgba(128, 128, 128, 0.2);
  border-radius: 12px;
  padding: 14px 16px;
  cursor: pointer;
  transition: border-color 0.2s ease, background 0.2s ease, transform 0.15s ease;
}

.mode-card:hover {
  border-color: rgba(124, 108, 240, 0.4);
  background: rgba(124, 108, 240, 0.04);
  transform: scale(1.01);
}

.mode-card-active {
  border-color: rgba(124, 108, 240, 0.65) !important;
  background: rgba(124, 108, 240, 0.08) !important;
  box-shadow: 0 0 0 3px rgba(124, 108, 240, 0.15);
}

.mode-card-top {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 4px;
}

.mode-name {
  font-size: 15px;
  font-weight: 700;
  font-family: monospace;
}

.mode-badge {
  font-size: 10px;
  background: rgba(24, 160, 88, 0.2);
  color: #18a058;
  border-radius: 4px;
  padding: 1px 6px;
  font-weight: 600;
}

.mode-desc {
  margin: 0;
  font-size: 12px;
  color: rgba(128, 128, 128, 0.7);
  line-height: 1.5;
}

.mode-radio {
  position: absolute;
  top: 12px;
  right: 12px;
  width: 16px;
  height: 16px;
  border-radius: 50%;
  border: 2px solid rgba(128, 128, 128, 0.3);
  display: flex;
  align-items: center;
  justify-content: center;
  transition: border-color 0.2s ease;
}

.mode-card-active .mode-radio { border-color: #7c6cf0; }

.mode-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: transparent;
  transition: background 0.2s ease;
}

.mode-dot-active { background: #7c6cf0; }

/* ── 浏览按钮 ── */
.browse-btn {
  padding: 0 14px;
  height: 34px;
  border-radius: 8px;
  border: 1px solid rgba(128, 128, 128, 0.25);
  cursor: pointer;
  background: transparent;
  color: rgba(128, 128, 128, 0.75);
  font-size: 13px;
  font-family: inherit;
  white-space: nowrap;
  transition: background 0.15s ease, transform 0.12s ease;
}

.browse-btn:hover {
  background: rgba(124, 108, 240, 0.1);
  color: #7c6cf0;
  transform: scale(1.02);
}

.browse-btn:active { transform: scale(0.97); }

/* ── 进度 ── */
.progress-wrap {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.progress-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 12px;
  color: rgba(128, 128, 128, 0.75);
}

.progress-pct { font-weight: 600; }

.progress-fade-enter-active,
.progress-fade-leave-active {
  transition: opacity 0.3s ease, transform 0.3s ease;
}

.progress-fade-enter-from,
.progress-fade-leave-to {
  opacity: 0;
  transform: translateY(6px);
}

/* ── 主操作按钮 ── */
.action-btn {
  min-width: 130px;
}
</style>
