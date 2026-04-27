<script setup>
import { ref, computed, onMounted, onUnmounted, h } from 'vue'
import { useMessage } from 'naive-ui'
import {
  DocumentOutline, KeyOutline, LockOpenOutline, FolderOpenOutline,
  CopyOutline, EyeOutline, EyeOffOutline, CloudUploadOutline, LibraryOutline,
} from '@vicons/ionicons5'
import { keys, addKey, findByHex } from '../stores/keyStore'

const message = useMessage()

// ── Wails 容错导入 ──
let SelectInputFile  = async () => '/tmp/demo.sm4'
let SelectOutputFile = async () => '/tmp/demo.txt'
let DecryptFile      = async () => { throw new Error('后端未就绪') }
let EventsOn         = () => {}
let EventsOff        = () => {}

;(async () => {
  try { ({ SelectInputFile, SelectOutputFile, DecryptFile } = await import('../../wailsjs/go/main/App')) } catch {}
  try { ({ EventsOn, EventsOff } = await import('../../wailsjs/runtime/runtime')) } catch {}
})()

// ── 状态 ──
const inputFile  = ref('')
const inputSize  = ref(0)
const key        = ref('')
const showKey    = ref(false)
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
    outputFile.value = path.endsWith('.sm4') ? path.slice(0, -4) : path + '.dec'
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
  outputFile.value = path.endsWith('.sm4') ? path.slice(0, -4) : path + '.dec'
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

function onKeyInput() {
  if (!selectedKeyId.value) return
  const item = keys.value.find(k => k.id === selectedKeyId.value)
  if (!item || item.hex.toLowerCase() !== key.value.toLowerCase()) {
    selectedKeyId.value = null
  }
}

function saveCurrentKey() {
  if (!key.value) {
    message.warning('请先输入密钥')
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

function copyKey() {
  if (!key.value) return
  navigator.clipboard?.writeText(key.value)
  message.success('密钥已复制到剪贴板')
}

onMounted(() => {
  try {
    EventsOn('decrypt:progress', (data) => {
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
  try { EventsOff('decrypt:progress') } catch {}
  if (window.runtime?.OnFileDropOff) window.runtime.OnFileDropOff()
})

// ── 解密 ──
async function handleDecrypt() {
  if (!inputFile.value) { message.warning('请先选择密文文件'); return }
  if (!key.value)        { message.warning('请输入解密密钥'); return }
  if (!outputFile.value) { message.warning('请指定输出文件路径'); return }

  running.value = true
  done.value    = false
  progress.value = 0
  processedBytes.value = 0

  try {
    await DecryptFile({
      inputPath: inputFile.value,
      outputPath: outputFile.value,
      keyHex: key.value
    })
    progress.value = 100
    done.value = true
    message.success('解密完成！')
  } catch (e) {
    message.error('解密失败：' + e.message)
  } finally {
    running.value = false
  }
}
</script>

<template>
  <n-card :bordered="false" size="large" class="panel-card">
    <template #header>
      <div class="panel-header">
        <n-icon :component="LockOpenOutline" :size="20" class="panel-icon-decrypt" />
        <span>文件解密</span>
      </div>
    </template>

    <n-space vertical :size="20">

      <!-- 自动读取 IV 的提示 -->
      <n-alert type="info" :show-icon="true" class="info-alert">
        解密时会自动从密文文件头读取加密模式与 IV，无需手动选择。
      </n-alert>

      <!-- 密文文件 Dropzone -->
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
          <div class="dz-title">拖拽 .sm4 密文文件到此处，或点击选择</div>
          <div class="dz-hint">支持 .sm4 格式密文文件</div>
        </template>
      </div>

      <!-- 密钥输入 -->
      <div class="field-group">
        <div class="field-label">
          <n-icon :component="KeyOutline" :size="14" />
          <span>解密密钥（128 bit / 16 字节）</span>
        </div>

        <!-- 密钥库下拉选择 -->
        <div class="key-row" v-if="keyOptions.length">
          <n-select
            v-model:value="selectedKeyId"
            :options="keyOptions"
            :render-label="renderKeyOption"
            placeholder="从密钥库选择已保存的密钥…"
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
            placeholder="输入解密密钥"
            class="key-input"
            :input-props="{ style: 'font-family: monospace' }"
            @input="onKeyInput"
          />
          <div class="key-actions">
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

      <!-- 输出路径 -->
      <div class="field-group">
        <div class="field-label">
          <n-icon :component="FolderOpenOutline" :size="14" />
          <span>输出路径</span>
        </div>
        <div class="key-row">
          <n-input v-model:value="outputFile" placeholder="解密后文件保存位置…" />
          <button class="browse-btn" @click="browseOutput">浏览</button>
        </div>
      </div>

      <!-- 进度条 -->
      <Transition name="progress-fade">
        <div v-if="running || progress > 0" class="progress-wrap">
          <div class="progress-header">
            <span>{{ running ? '解密中…' : (done ? '完成' : '就绪') }}</span>
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
          title="解密成功"
        >
          <template #default>
            文件已还原至：<code style="word-break: break-all">{{ outputFile }}</code>
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
          @click="handleDecrypt"
          class="action-btn"
        >
          <template #icon>
            <n-icon :component="running ? undefined : LockOpenOutline" />
          </template>
          {{ running ? '解密中…' : '开始解密' }}
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

.panel-icon-decrypt { color: #4ab8d4; }

.info-alert { border-radius: 10px !important; }

.dropzone {
  border: 2px dashed rgba(74, 184, 212, 0.4);
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
  border-color: rgba(74, 184, 212, 0.75);
  background: rgba(74, 184, 212, 0.06);
  transform: scale(1.005);
}

.dz-filled {
  border-style: solid;
  border-color: rgba(74, 184, 212, 0.5);
  background: rgba(74, 184, 212, 0.04);
}

.dz-upload-icon { color: rgba(74, 184, 212, 0.5); }
.dz-file-icon   { color: #4ab8d4; }

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

.dz-size  { font-size: 12px; color: rgba(128, 128, 128, 0.7); }
.dz-hint  { font-size: 11px; color: rgba(128, 128, 128, 0.5); }

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

.key-row {
  display: flex;
  gap: 8px;
  align-items: center;
}

.key-input { flex: 1; }

.key-actions { display: flex; gap: 4px; }

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
  background: rgba(74, 184, 212, 0.12);
  color: #4ab8d4;
  transform: scale(1.05);
}

.key-btn:active:not(:disabled) { transform: scale(0.95); }
.key-btn:disabled { opacity: 0.35; cursor: not-allowed; }

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
  background: rgba(74, 184, 212, 0.1);
  color: #4ab8d4;
  transform: scale(1.02);
}

.browse-btn:active { transform: scale(0.97); }

.progress-wrap { display: flex; flex-direction: column; gap: 6px; }

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

.action-btn { min-width: 130px; }
</style>
