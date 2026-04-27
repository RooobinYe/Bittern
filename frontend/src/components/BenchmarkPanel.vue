<script setup>
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useMessage } from 'naive-ui'
import * as echarts from 'echarts/core'
import { BarChart } from 'echarts/charts'
import { GridComponent, TooltipComponent, LegendComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import {
  SpeedometerOutline, DocumentOutline, FlashOutline, TrophyOutline,
} from '@vicons/ionicons5'

echarts.use([BarChart, GridComponent, TooltipComponent, LegendComponent, CanvasRenderer])

const message = useMessage()

// ── Wails 容错导入 ──
let RunBenchmark = async () => { throw new Error('后端未就绪') }
;(async () => {
  try { ({ RunBenchmark } = await import('../../wailsjs/go/main/App')) } catch {}
})()

// ── 状态 ──
const fileSize   = ref('1MB')
const running    = ref(false)
const skeletonOn = ref(false)
const results    = ref([])
const chartRef   = ref(null)
let   chartInstance = null

const sizeCards = [
  { value: '1KB',   label: '1 KB',   icon: DocumentOutline },
  { value: '1MB',   label: '1 MB',   icon: DocumentOutline },
  { value: '10MB',  label: '10 MB',  icon: DocumentOutline },
  { value: '100MB', label: '100 MB', icon: DocumentOutline },
]

// KPI
const cbcResult = computed(() => results.value.find(r => r.mode === 'CBC'))
const ctrResult = computed(() => results.value.find(r => r.mode === 'CTR'))
const winner    = computed(() => {
  if (!cbcResult.value || !ctrResult.value) return ''
  const cbcTh = parseFloat(cbcResult.value.throughputMBps) || 0
  const ctrTh = parseFloat(ctrResult.value.throughputMBps) || 0
  return cbcTh >= ctrTh ? 'CBC' : 'CTR'
})

// 列配置
const columns = [
  { title: '模式', key: 'mode', width: 80 },
  { title: '加密耗时 (ms)', key: 'encryptMs' },
  { title: '解密耗时 (ms)', key: 'decryptMs' },
  { title: '吞吐率 (MB/s)', key: 'throughputMBps' },
]

// ── ECharts ──
function initChart() {
  if (!chartRef.value) return
  if (chartInstance) { chartInstance.dispose(); chartInstance = null }
  chartInstance = echarts.init(chartRef.value)
  renderChart()
}

function renderChart() {
  if (!chartInstance || !results.value.length) return
  const modes     = results.value.map(r => r.mode)
  const encryptMs = results.value.map(r => r.encryptMs)
  const decryptMs = results.value.map(r => r.decryptMs)

  const isDark = document.body.classList.contains('dark') ||
    window.matchMedia('(prefers-color-scheme: dark)').matches

  chartInstance.setOption({
    backgroundColor: 'transparent',
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow' },
      backgroundColor: isDark ? 'rgba(20,20,40,0.9)' : 'rgba(255,255,255,0.95)',
      borderColor: isDark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.08)',
      textStyle: { color: isDark ? '#fff' : '#222', fontSize: 12 },
    },
    legend: {
      data: ['加密耗时 (ms)', '解密耗时 (ms)'],
      textStyle: { color: isDark ? 'rgba(255,255,255,0.6)' : 'rgba(0,0,0,0.55)', fontSize: 12 },
      top: 4,
    },
    grid: { left: 40, right: 20, top: 40, bottom: 30 },
    xAxis: {
      type: 'category',
      data: modes,
      axisLabel: { color: isDark ? 'rgba(255,255,255,0.55)' : 'rgba(0,0,0,0.5)', fontSize: 13, fontWeight: 700 },
      axisLine: { lineStyle: { color: isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.12)' } },
    },
    yAxis: {
      type: 'value',
      name: 'ms',
      nameTextStyle: { color: isDark ? 'rgba(255,255,255,0.35)' : 'rgba(0,0,0,0.35)', fontSize: 11 },
      axisLabel: { color: isDark ? 'rgba(255,255,255,0.45)' : 'rgba(0,0,0,0.4)', fontSize: 11 },
      splitLine: { lineStyle: { color: isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)' } },
    },
    series: [
      {
        name: '加密耗时 (ms)',
        type: 'bar',
        data: encryptMs,
        barWidth: '32%',
        itemStyle: {
          color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
            { offset: 0, color: '#a78bf0' },
            { offset: 1, color: '#6c4de0' },
          ]),
          borderRadius: [6, 6, 0, 0],
        },
      },
      {
        name: '解密耗时 (ms)',
        type: 'bar',
        data: decryptMs,
        barWidth: '32%',
        itemStyle: {
          color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
            { offset: 0, color: '#6fd4e8' },
            { offset: 1, color: '#2a9cb8' },
          ]),
          borderRadius: [6, 6, 0, 0],
        },
      },
    ],
  })
}

watch(results, async () => {
  await nextTick()
  if (chartRef.value && results.value.length) {
    initChart()
  }
})

onMounted(() => {
  window.addEventListener('resize', () => chartInstance?.resize())
})

onUnmounted(() => {
  chartInstance?.dispose()
  window.removeEventListener('resize', () => chartInstance?.resize())
})

// ── 跑 Benchmark ──
async function runBenchmark() {
  running.value  = true
  skeletonOn.value = true
  results.value  = []

  try {
    const res = await RunBenchmark(fileSize.value)
    results.value = res
  } catch {
    // 后端未就绪时用模拟数据演示 UI
    await new Promise(r => setTimeout(r, 600))
    const sizeMb = {
      '1KB': 0.001, '1MB': 1, '10MB': 10, '100MB': 100,
    }[fileSize.value] ?? 1

    const cbcEncMs = +(sizeMb * 42 + Math.random() * 8).toFixed(2)
    const cbcDecMs = +(sizeMb * 38 + Math.random() * 8).toFixed(2)
    const ctrEncMs = +(sizeMb * 18 + Math.random() * 6).toFixed(2)
    const ctrDecMs = +(sizeMb * 17 + Math.random() * 6).toFixed(2)
    results.value = [
      { mode: 'CBC', encryptMs: cbcEncMs, decryptMs: cbcDecMs, throughputMBps: (sizeMb / (cbcEncMs / 1000)).toFixed(2) },
      { mode: 'CTR', encryptMs: ctrEncMs, decryptMs: ctrDecMs, throughputMBps: (sizeMb / (ctrEncMs / 1000)).toFixed(2) },
    ]
    message.info('后端未就绪，展示模拟数据')
  } finally {
    running.value    = false
    skeletonOn.value = false
  }
}
</script>

<template>
  <n-card :bordered="false" size="large">
    <template #header>
      <div class="panel-header">
        <n-icon :component="SpeedometerOutline" :size="20" class="panel-icon-bench" />
        <span>加解密效率对比</span>
      </div>
    </template>

    <n-space vertical :size="20">

      <!-- 数据大小选择 -->
      <div class="field-group">
        <div class="field-label">
          <n-icon :component="DocumentOutline" :size="14" />
          <span>测试数据大小</span>
        </div>
        <div class="size-cards">
          <div
            v-for="s in sizeCards"
            :key="s.value"
            class="size-card"
            :class="{ 'size-card-active': fileSize === s.value }"
            @click="fileSize = s.value"
          >
            <n-icon :component="s.icon" :size="16" class="size-icon" />
            <span class="size-label">{{ s.label }}</span>
          </div>
        </div>
      </div>

      <!-- 操作按钮 -->
      <n-space justify="end">
        <n-button
          type="primary"
          size="large"
          :loading="running"
          :disabled="running"
          @click="runBenchmark"
          class="bench-btn"
        >
          <template #icon>
            <n-icon :component="FlashOutline" />
          </template>
          {{ running ? '测试中…' : '开始对比' }}
        </n-button>
      </n-space>

      <!-- Skeleton 占位 -->
      <template v-if="skeletonOn">
        <n-skeleton height="220px" :sharp="false" style="border-radius: 12px" />
        <div style="display: flex; gap: 12px">
          <n-skeleton v-for="i in 3" :key="i" height="80px" :sharp="false" style="flex: 1; border-radius: 12px" />
        </div>
      </template>

      <!-- 结果区 -->
      <Transition name="result-fade">
        <div v-if="results.length && !skeletonOn">

          <!-- KPI 卡片 -->
          <div class="kpi-row">
            <div class="kpi-card">
              <div class="kpi-label">CBC 吞吐率</div>
              <div class="kpi-value cbc-color">{{ cbcResult?.throughputMBps ?? '—' }} <span class="kpi-unit">MB/s</span></div>
            </div>
            <div class="kpi-card">
              <div class="kpi-label">CTR 吞吐率</div>
              <div class="kpi-value ctr-color">{{ ctrResult?.throughputMBps ?? '—' }} <span class="kpi-unit">MB/s</span></div>
            </div>
            <div class="kpi-card kpi-winner">
              <div class="kpi-label">
                <n-icon :component="TrophyOutline" :size="13" style="margin-right: 4px; color: #f0a020" />
                优胜模式
              </div>
              <div class="kpi-value winner-color">{{ winner || '—' }}</div>
            </div>
          </div>

          <!-- ECharts 双柱状图 -->
          <div ref="chartRef" class="chart-area" />

          <!-- 详情表格 -->
          <n-data-table
            :columns="columns"
            :data="results"
            :bordered="false"
            size="small"
            style="margin-top: 16px"
          />
        </div>
      </Transition>

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

.panel-icon-bench { color: #e87d20; }

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

/* ── 大小卡片 ── */
.size-cards {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
}

.size-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 5px;
  padding: 12px 18px;
  border-radius: 12px;
  border: 1px solid rgba(128, 128, 128, 0.2);
  cursor: pointer;
  transition: border-color 0.2s ease, background 0.2s ease, transform 0.15s ease;
  min-width: 72px;
}

.size-card:hover {
  border-color: rgba(232, 125, 32, 0.45);
  background: rgba(232, 125, 32, 0.05);
  transform: scale(1.03);
}

.size-card-active {
  border-color: rgba(232, 125, 32, 0.65) !important;
  background: rgba(232, 125, 32, 0.08) !important;
  box-shadow: 0 0 0 3px rgba(232, 125, 32, 0.15);
}

.size-icon { color: rgba(232, 125, 32, 0.6); }
.size-card-active .size-icon { color: #e87d20; }

.size-label {
  font-size: 13px;
  font-weight: 600;
}

/* ── KPI ── */
.kpi-row {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 10px;
  margin-bottom: 16px;
}

.kpi-card {
  border-radius: 12px;
  border: 1px solid rgba(128, 128, 128, 0.15);
  padding: 14px 16px;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.kpi-winner { border-color: rgba(240, 160, 32, 0.3); background: rgba(240, 160, 32, 0.04); }

.kpi-label {
  font-size: 11px;
  color: rgba(128, 128, 128, 0.6);
  display: flex;
  align-items: center;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.kpi-value {
  font-size: 22px;
  font-weight: 700;
  font-feature-settings: "tnum";
}

.kpi-unit { font-size: 12px; font-weight: 400; color: rgba(128, 128, 128, 0.55); }

.cbc-color    { color: #a78bf0; }
.ctr-color    { color: #4ab8d4; }
.winner-color { color: #f0a020; }

/* ── Chart ── */
.chart-area {
  width: 100%;
  height: 220px;
  border-radius: 12px;
  overflow: hidden;
}

.bench-btn { min-width: 130px; }

/* ── 结果渐入 ── */
.result-fade-enter-active {
  transition: opacity 0.4s ease, transform 0.4s ease;
}

.result-fade-enter-from {
  opacity: 0;
  transform: translateY(10px);
}
</style>
