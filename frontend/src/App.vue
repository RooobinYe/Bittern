<script setup>
import { ref, computed, onMounted } from 'vue'
import { darkTheme, zhCN, dateZhCN } from 'naive-ui'
import { LockClosedOutline, LockOpenOutline, KeyOutline, SpeedometerOutline, MoonOutline, SunnyOutline, LogoGithub } from '@vicons/ionicons5'
import { NIcon } from 'naive-ui'
import EncryptPanel from './components/EncryptPanel.vue'
import DecryptPanel from './components/DecryptPanel.vue'
import KeyManager from './components/KeyManager.vue'
import BenchmarkPanel from './components/BenchmarkPanel.vue'

const isDark = ref(true)
const activeTab = ref('encrypt')
const mounted = ref(false)

onMounted(() => {
  setTimeout(() => { mounted.value = true }, 50)
})

const themeOverrides = computed(() => ({
  common: {
    borderRadius: '10px',
    borderRadiusSmall: '8px',
  },
  Card: {
    borderRadius: '16px',
  },
}))

const tabs = [
  { name: 'encrypt',   label: '加密',     icon: LockClosedOutline  },
  { name: 'decrypt',   label: '解密',     icon: LockOpenOutline    },
  { name: 'key',       label: '密钥管理', icon: KeyOutline         },
  { name: 'benchmark', label: '效率对比', icon: SpeedometerOutline  },
]
</script>

<template>
  <n-config-provider
    :theme="isDark ? darkTheme : null"
    :theme-overrides="themeOverrides"
    :locale="zhCN"
    :date-locale="dateZhCN"
  >
    <n-message-provider>
      <n-dialog-provider>
        <n-notification-provider>

          <!-- 动态背景 -->
          <div class="app-bg" :class="isDark ? 'dark' : 'light'">
            <div class="orb-1" />
            <div class="orb-2" />
            <div class="orb-3" />
          </div>

          <!-- 主壳 -->
          <div class="app-shell" :class="isDark ? 'dark' : 'light'">

            <!-- Header -->
            <header
              class="app-header glass-card"
              :class="[isDark ? 'header-dark' : 'header-light', mounted ? 'stagger-enter' : '']"
              style="animation-delay: 0ms"
            >
              <div class="header-left">
                <span class="header-logo">🔐</span>
                <div class="header-text">
                  <span class="header-title">SM4 文件加解密</span>
                  <span class="header-sub">基于 SM4 的文件加解密工具</span>
                </div>
              </div>

              <div class="header-right">
                <!-- 主题切换 -->
                <n-tooltip>
                  <template #trigger>
                    <button class="icon-btn" @click="isDark = !isDark" :class="isDark ? 'icon-btn-dark' : 'icon-btn-light'">
                      <n-icon :component="isDark ? SunnyOutline : MoonOutline" :size="18" />
                    </button>
                  </template>
                  {{ isDark ? '切换亮色主题' : '切换暗色主题' }}
                </n-tooltip>
                <!-- GitHub 占位 -->
                <n-tooltip>
                  <template #trigger>
                    <button class="icon-btn" :class="isDark ? 'icon-btn-dark' : 'icon-btn-light'" @click="() => {}">
                      <n-icon :component="LogoGithub" :size="18" />
                    </button>
                  </template>
                  GitHub
                </n-tooltip>
              </div>
            </header>

            <!-- Tab 导航 -->
            <nav
              class="app-nav"
              :class="[mounted ? 'stagger-enter' : '']"
              style="animation-delay: 80ms"
            >
              <div class="tab-group glass-card" :class="isDark ? 'tab-dark' : 'tab-light'">
                <button
                  v-for="tab in tabs"
                  :key="tab.name"
                  class="tab-btn"
                  :class="[
                    activeTab === tab.name ? (isDark ? 'tab-active-dark' : 'tab-active-light') : (isDark ? 'tab-inactive-dark' : 'tab-inactive-light')
                  ]"
                  @click="activeTab = tab.name"
                >
                  <n-icon :component="tab.icon" :size="16" class="tab-icon" />
                  <span>{{ tab.label }}</span>
                </button>
              </div>
            </nav>

            <!-- 内容区 -->
            <main class="app-content">
              <div class="content-inner">
                <Transition name="tab-fade" mode="out-in">
                  <div
                    :key="activeTab"
                    class="tab-content"
                    :class="mounted ? 'stagger-enter' : ''"
                    style="animation-delay: 140ms"
                  >
                    <EncryptPanel   v-if="activeTab === 'encrypt'"   />
                    <DecryptPanel   v-if="activeTab === 'decrypt'"   />
                    <KeyManager     v-if="activeTab === 'key'"       />
                    <BenchmarkPanel v-if="activeTab === 'benchmark'" />
                  </div>
                </Transition>
              </div>
            </main>

          </div>

        </n-notification-provider>
      </n-dialog-provider>
    </n-message-provider>
  </n-config-provider>
</template>

<style scoped>
/* ── Header ── */
.app-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin: 16px 24px 0;
  padding: 14px 20px;
  flex-shrink: 0;
}

.header-dark {
  background: rgba(255, 255, 255, 0.06) !important;
  border: 1px solid rgba(255, 255, 255, 0.1) !important;
  box-shadow: 0 2px 20px rgba(0, 0, 0, 0.35), inset 0 1px 0 rgba(255, 255, 255, 0.08) !important;
}

.header-light {
  background: rgba(255, 255, 255, 0.6) !important;
  border: 1px solid rgba(255, 255, 255, 0.8) !important;
  box-shadow: 0 2px 20px rgba(0, 0, 0, 0.07), inset 0 1px 0 rgba(255, 255, 255, 0.95) !important;
}

.header-left {
  display: flex;
  align-items: center;
  gap: 12px;
}

.header-logo {
  font-size: 28px;
  line-height: 1;
}

.header-text {
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.header-title {
  font-size: 15px;
  font-weight: 700;
  letter-spacing: -0.01em;
}

.dark .header-title { color: rgba(255, 255, 255, 0.92); }
.light .header-title { color: rgba(0, 0, 0, 0.82); }

.header-sub {
  font-size: 11px;
  letter-spacing: 0.01em;
}

.dark .header-sub  { color: rgba(255, 255, 255, 0.42); }
.light .header-sub { color: rgba(0, 0, 0, 0.38); }

.header-right {
  display: flex;
  align-items: center;
  gap: 8px;
}

/* ── 图标按钮 ── */
.icon-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 34px;
  height: 34px;
  border-radius: 10px;
  border: none;
  cursor: pointer;
  transition: transform 0.15s ease, background 0.2s ease;
}

.icon-btn:hover  { transform: scale(1.08); }
.icon-btn:active { transform: scale(0.93); }

.icon-btn-dark {
  background: rgba(255, 255, 255, 0.08);
  color: rgba(255, 255, 255, 0.7);
}

.icon-btn-dark:hover { background: rgba(255, 255, 255, 0.14); }

.icon-btn-light {
  background: rgba(0, 0, 0, 0.05);
  color: rgba(0, 0, 0, 0.55);
}

.icon-btn-light:hover { background: rgba(0, 0, 0, 0.1); }

/* ── Tab 导航 ── */
.app-nav {
  margin: 12px 24px 0;
  flex-shrink: 0;
}

.tab-group {
  display: inline-flex;
  gap: 4px;
  padding: 5px;
}

.tab-dark {
  background: rgba(255, 255, 255, 0.05) !important;
  border: 1px solid rgba(255, 255, 255, 0.08) !important;
  box-shadow: 0 1px 12px rgba(0, 0, 0, 0.3) !important;
}

.tab-light {
  background: rgba(255, 255, 255, 0.5) !important;
  border: 1px solid rgba(255, 255, 255, 0.7) !important;
  box-shadow: 0 1px 12px rgba(0, 0, 0, 0.06) !important;
}

.tab-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 7px 16px;
  border-radius: 10px;
  border: none;
  cursor: pointer;
  font-size: 13px;
  font-weight: 500;
  font-family: inherit;
  transition: background 0.2s ease, color 0.2s ease, transform 0.15s ease, box-shadow 0.2s ease;
}

.tab-btn:hover  { transform: scale(1.02); }
.tab-btn:active { transform: scale(0.97); }

.tab-icon { flex-shrink: 0; }

/* 激活态 – 暗色 */
.tab-active-dark {
  background: rgba(120, 100, 240, 0.65);
  color: rgba(255, 255, 255, 0.95);
  box-shadow: 0 2px 12px rgba(120, 100, 240, 0.45);
}

/* 激活态 – 亮色 */
.tab-active-light {
  background: rgba(255, 255, 255, 0.92);
  color: rgba(60, 60, 220, 0.9);
  box-shadow: 0 2px 10px rgba(60, 60, 220, 0.15);
}

/* 非激活 – 暗色 */
.tab-inactive-dark {
  background: transparent;
  color: rgba(255, 255, 255, 0.45);
}

.tab-inactive-dark:hover {
  background: rgba(255, 255, 255, 0.06);
  color: rgba(255, 255, 255, 0.75);
}

/* 非激活 – 亮色 */
.tab-inactive-light {
  background: transparent;
  color: rgba(0, 0, 0, 0.4);
}

.tab-inactive-light:hover {
  background: rgba(0, 0, 0, 0.04);
  color: rgba(0, 0, 0, 0.7);
}

/* ── 内容区 ── */
.tab-content {
  padding-top: 16px;
}
</style>
