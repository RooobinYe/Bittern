<script setup>
import { ref } from 'vue'

const fileSize = ref('1MB')
const running = ref(false)
const results = ref([])

function runBenchmark() {
  // TODO: 调用 Wails 后端 RunBenchmark(size) 返回 [{mode, encryptMs, decryptMs, throughput}]
  running.value = true
  setTimeout(() => {
    results.value = [
      { mode: 'CBC', encryptMs: 0, decryptMs: 0, throughput: '—' },
      { mode: 'CFB', encryptMs: 0, decryptMs: 0, throughput: '—' },
    ]
    running.value = false
  }, 300)
}

const columns = [
  { title: '模式', key: 'mode' },
  { title: '加密耗时 (ms)', key: 'encryptMs' },
  { title: '解密耗时 (ms)', key: 'decryptMs' },
  { title: '吞吐率 (MB/s)', key: 'throughput' },
]
</script>

<template>
  <n-card title="加解密效率对比" :bordered="false" size="large">
    <n-space vertical size="large">
      <n-form-item label="测试数据大小" label-placement="left" :show-feedback="false">
        <n-radio-group v-model:value="fileSize">
          <n-radio-button value="1KB">1 KB</n-radio-button>
          <n-radio-button value="1MB">1 MB</n-radio-button>
          <n-radio-button value="10MB">10 MB</n-radio-button>
          <n-radio-button value="100MB">100 MB</n-radio-button>
        </n-radio-group>
      </n-form-item>

      <n-space justify="end">
        <n-button type="primary" size="large" @click="runBenchmark" :loading="running">
          开始对比
        </n-button>
      </n-space>

      <n-data-table
        v-if="results.length > 0"
        :columns="columns"
        :data="results"
        :bordered="false"
      />
    </n-space>
  </n-card>
</template>
