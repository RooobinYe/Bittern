<script setup>
import { ref } from 'vue'
import { darkTheme, zhCN, dateZhCN } from 'naive-ui'
import EncryptPanel from './components/EncryptPanel.vue'
import DecryptPanel from './components/DecryptPanel.vue'
import KeyManager from './components/KeyManager.vue'
import BenchmarkPanel from './components/BenchmarkPanel.vue'

const isDark = ref(true)
const activeTab = ref('encrypt')
</script>

<template>
  <n-config-provider
    :theme="isDark ? darkTheme : null"
    :locale="zhCN"
    :date-locale="dateZhCN"
  >
    <n-message-provider>
      <n-dialog-provider>
        <n-notification-provider>
          <div class="app-shell">
            <header class="app-header">
              <div class="title">
                <span class="logo">🔐</span>
                <span>SM4 文件加解密工具</span>
              </div>
              <n-switch v-model:value="isDark" size="small">
                <template #checked>暗</template>
                <template #unchecked>亮</template>
              </n-switch>
            </header>

            <n-tabs
              v-model:value="activeTab"
              type="line"
              size="large"
              class="app-tabs"
              pane-class="app-tab-pane"
              animated
            >
              <n-tab-pane name="encrypt" tab="加密">
                <EncryptPanel />
              </n-tab-pane>
              <n-tab-pane name="decrypt" tab="解密">
                <DecryptPanel />
              </n-tab-pane>
              <n-tab-pane name="key" tab="密钥">
                <KeyManager />
              </n-tab-pane>
              <n-tab-pane name="benchmark" tab="效率对比">
                <BenchmarkPanel />
              </n-tab-pane>
            </n-tabs>
          </div>
        </n-notification-provider>
      </n-dialog-provider>
    </n-message-provider>
  </n-config-provider>
</template>

<style>
.app-shell {
  display: flex;
  flex-direction: column;
  height: 100vh;
  padding: 16px 24px 0;
  box-sizing: border-box;
}

.app-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 8px;
}

.app-header .title {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 16px;
  font-weight: 600;
}

.app-header .logo {
  font-size: 20px;
}

.app-tabs {
  flex: 1;
  min-height: 0;
}

.app-tab-pane {
  height: 100%;
  padding-top: 8px;
  overflow: auto;
}
</style>
