<script setup>
import { ref } from 'vue'

const inputFile = ref('')
const key = ref('')
const outputFile = ref('')
const progress = ref(0)
const running = ref(false)

function handleDecrypt() {
  // TODO: 调用 Wails 后端 DecryptFile()
  console.log({ inputFile: inputFile.value, key: key.value, outputFile: outputFile.value })
}
</script>

<template>
  <n-card title="文件解密" :bordered="false" size="large">
    <n-space vertical size="large">
      <n-alert type="info" :show-icon="true" style="margin-bottom: 8px">
        解密时会自动从密文文件头读取加密模式与 IV，无需手动选择。
      </n-alert>

      <n-form-item label="密文文件" label-placement="left" :show-feedback="false">
        <n-input v-model:value="inputFile" placeholder="选择待解密的密文文件…" readonly />
        <n-button style="margin-left: 8px">浏览</n-button>
      </n-form-item>

      <n-form-item label="密钥 (16字节)" label-placement="left" :show-feedback="false">
        <n-input
          v-model:value="key"
          type="password"
          show-password-on="click"
          placeholder="输入解密密钥"
        />
      </n-form-item>

      <n-form-item label="输出文件" label-placement="left" :show-feedback="false">
        <n-input v-model:value="outputFile" placeholder="解密后文件保存位置…" readonly />
        <n-button style="margin-left: 8px">浏览</n-button>
      </n-form-item>

      <n-progress
        v-if="running || progress > 0"
        type="line"
        :percentage="progress"
        :height="12"
        :border-radius="6"
      />

      <n-space justify="end">
        <n-button type="primary" size="large" @click="handleDecrypt" :loading="running">
          开始解密
        </n-button>
      </n-space>
    </n-space>
  </n-card>
</template>
