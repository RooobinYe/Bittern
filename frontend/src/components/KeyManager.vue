<script setup>
import { ref } from 'vue'

const currentKey = ref('')
const keyHex = ref('')

function generateKey() {
  // TODO: 调用 Wails 后端 GenerateKey()，返回 16 字节随机密钥
  const bytes = new Uint8Array(16)
  crypto.getRandomValues(bytes)
  keyHex.value = Array.from(bytes).map((b) => b.toString(16).padStart(2, '0')).join('')
  currentKey.value = keyHex.value
}

function copyKey() {
  // TODO: 复制到剪贴板
  navigator.clipboard?.writeText(currentKey.value)
}
</script>

<template>
  <n-card title="密钥管理" :bordered="false" size="large">
    <n-space vertical size="large">
      <n-alert type="warning" :show-icon="true">
        SM4 密钥固定为 128 bit（16 字节）。这里以十六进制展示，方便复制粘贴。
      </n-alert>

      <n-form-item label="当前密钥" label-placement="left" :show-feedback="false">
        <n-input v-model:value="currentKey" placeholder="尚未生成密钥" readonly />
        <n-button style="margin-left: 8px" @click="copyKey" :disabled="!currentKey">
          复制
        </n-button>
      </n-form-item>

      <n-space justify="end">
        <n-button type="primary" size="large" @click="generateKey">
          随机生成 16 字节密钥
        </n-button>
      </n-space>

      <n-divider />

      <n-text depth="3">
        提示：实际项目中可使用密码 + 盐 (PBKDF2) 派生密钥，避免直接保存明文密钥。
      </n-text>
    </n-space>
  </n-card>
</template>
