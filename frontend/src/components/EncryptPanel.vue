<script setup>
import { ref } from 'vue'

const inputFile = ref('')
const key = ref('')
const mode = ref('CBC')
const outputFile = ref('')
const progress = ref(0)
const running = ref(false)

function handleEncrypt() {
  // TODO: 调用 Wails 后端 EncryptFile()
  console.log({ inputFile: inputFile.value, key: key.value, mode: mode.value, outputFile: outputFile.value })
}
</script>

<template>
  <n-card title="文件加密" :bordered="false" size="large">
    <n-space vertical size="large">
      <n-form-item label="输入文件" label-placement="left" :show-feedback="false">
        <n-input v-model:value="inputFile" placeholder="选择待加密的文件…" readonly />
        <n-button style="margin-left: 8px">浏览</n-button>
      </n-form-item>

      <n-form-item label="密钥 (16字节)" label-placement="left" :show-feedback="false">
        <n-input
          v-model:value="key"
          type="password"
          show-password-on="click"
          placeholder="输入 SM4 加密密钥（128 bit）"
        />
        <n-button style="margin-left: 8px">随机生成</n-button>
      </n-form-item>

      <n-form-item label="加密模式" label-placement="left" :show-feedback="false">
        <n-radio-group v-model:value="mode">
          <n-radio-button value="CBC">CBC（密码分组链接）</n-radio-button>
          <n-radio-button value="CFB">CFB（密码反馈）</n-radio-button>
        </n-radio-group>
      </n-form-item>

      <n-form-item label="输出文件" label-placement="left" :show-feedback="false">
        <n-input v-model:value="outputFile" placeholder="加密后文件保存位置…" readonly />
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
        <n-button type="primary" size="large" @click="handleEncrypt" :loading="running">
          开始加密
        </n-button>
      </n-space>
    </n-space>
  </n-card>
</template>
