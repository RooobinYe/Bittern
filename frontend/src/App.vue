<script setup>
import { ref, computed, nextTick, onMounted, onUnmounted, watch } from 'vue'
import { darkTheme, zhCN, dateZhCN } from 'naive-ui'
import { LockClosedOutline, LockOpenOutline, KeyOutline, SpeedometerOutline, MoonOutline, SunnyOutline, ContrastOutline, LogoGithub } from '@vicons/ionicons5'
import { NIcon } from 'naive-ui'
import EncryptPanel from './components/EncryptPanel.vue'
import DecryptPanel from './components/DecryptPanel.vue'
import KeyManager from './components/KeyManager.vue'
import BenchmarkPanel from './components/BenchmarkPanel.vue'
import TwemojiIcon from './components/TwemojiIcon.vue'

const STORAGE_KEY = 'bittern.themeMode'
const savedMode = localStorage.getItem(STORAGE_KEY)
const themeMode = ref(['auto', 'light', 'dark'].includes(savedMode) ? savedMode : 'auto')
const systemDark = ref(false)
const activeTab = ref('encrypt')
const mounted = ref(false)
const contentRef = ref(null)

let mediaQuery = null
const handleSystemThemeChange = (e) => { systemDark.value = e.matches }

onMounted(() => {
  mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
  systemDark.value = mediaQuery.matches
  mediaQuery.addEventListener('change', handleSystemThemeChange)
  setTimeout(() => { mounted.value = true }, 50)
})

onUnmounted(() => {
  if (mediaQuery) mediaQuery.removeEventListener('change', handleSystemThemeChange)
})

watch(themeMode, (val) => { localStorage.setItem(STORAGE_KEY, val) })

watch(activeTab, async () => {
  await nextTick()
  if (contentRef.value) contentRef.value.scrollTop = 0
})

const isDark = computed(() =>
  themeMode.value === 'auto' ? systemDark.value : themeMode.value === 'dark'
)

const themeOptions = [
  { value: 'auto',  icon: ContrastOutline, tip: '跟随系统' },
  { value: 'light', icon: SunnyOutline,    tip: '亮色主题' },
  { value: 'dark',  icon: MoonOutline,     tip: '暗色主题' },
]

const GITHUB_URL = 'https://github.com/RooobinYe/Bittern'
const openGithub = async () => {
  try {
    const { BrowserOpenURL } = await import('../wailsjs/runtime/runtime')
    BrowserOpenURL(GITHUB_URL)
  } catch {
    window.open(GITHUB_URL, '_blank')
  }
}

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

const activeTabIndex = computed(() =>
  Math.max(0, tabs.findIndex(tab => tab.name === activeTab.value))
)
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

            <div class="top-chrome" :class="isDark ? 'top-chrome-dark' : 'top-chrome-light'">
              <!-- Header -->
              <header
                class="app-header glass-card"
                :class="[isDark ? 'header-dark' : 'header-light', mounted ? 'stagger-enter' : '']"
                style="animation-delay: 0ms"
              >
                <div class="header-left">
                  <TwemojiIcon codepoint="1f510" label="SM4 文件加解密" class="header-logo" />
                  <div class="header-text">
                    <span class="header-title">SM4 文件加解密</span>
                    <span class="header-sub">基于 SM4 的文件加解密工具</span>
                  </div>
                </div>

                <div class="header-right">
                  <!-- 主题切换：自动 / 亮 / 暗 -->
                  <div class="theme-switcher" :class="isDark ? 'switcher-dark' : 'switcher-light'">
                    <n-tooltip v-for="opt in themeOptions" :key="opt.value">
                      <template #trigger>
                        <button
                          class="theme-btn"
                          :class="[
                            themeMode === opt.value
                              ? (isDark ? 'theme-btn-active-dark' : 'theme-btn-active-light')
                              : (isDark ? 'theme-btn-inactive-dark' : 'theme-btn-inactive-light')
                          ]"
                          @click="themeMode = opt.value"
                        >
                          <n-icon :component="opt.icon" :size="15" />
                        </button>
                      </template>
                      {{ opt.tip }}
                    </n-tooltip>
                  </div>
                  <!-- GitHub -->
                  <n-tooltip>
                    <template #trigger>
                      <button class="icon-btn" :class="isDark ? 'icon-btn-dark' : 'icon-btn-light'" @click="openGithub">
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
                <div class="nav-inner">
                  <div
                    class="tab-group glass-card"
                    :class="isDark ? 'tab-dark' : 'tab-light'"
                    :style="{ '--tab-index': activeTabIndex }"
                  >
                    <span class="tab-slider" aria-hidden="true" />
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
                </div>
              </nav>
            </div>

            <!-- 内容区 -->
            <main ref="contentRef" class="app-content">
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
/* ── 顶部液态玻璃层 ── */
.top-chrome {
  position: absolute;
  inset: 0 0 auto;
  z-index: 10;
  padding-bottom: 8px;
  pointer-events: none;
}

.top-chrome::before {
  content: '';
  position: absolute;
  inset: 0 0 -18px;
  pointer-events: none;
  backdrop-filter: blur(28px) saturate(1.45);
  -webkit-backdrop-filter: blur(28px) saturate(1.45);
  -webkit-mask-image: linear-gradient(to bottom, #000 0%, #000 74%, transparent 100%);
  mask-image: linear-gradient(to bottom, #000 0%, #000 74%, transparent 100%);
}

.top-chrome-light::before {
  background:
    linear-gradient(to bottom, rgba(248, 251, 255, 0.7), rgba(248, 251, 255, 0.42) 62%, rgba(248, 251, 255, 0)),
    radial-gradient(circle at 18% 24%, rgba(255, 255, 255, 0.58), transparent 28%),
    radial-gradient(circle at 76% 20%, rgba(160, 190, 255, 0.18), transparent 34%);
  box-shadow: inset 0 -1px 0 rgba(255, 255, 255, 0.46);
}

.top-chrome-dark::before {
  background:
    linear-gradient(to bottom, rgba(10, 12, 24, 0.66), rgba(12, 15, 30, 0.42) 64%, rgba(12, 15, 30, 0)),
    radial-gradient(circle at 22% 18%, rgba(130, 116, 255, 0.16), transparent 34%),
    radial-gradient(circle at 78% 16%, rgba(70, 190, 210, 0.1), transparent 36%);
  box-shadow: inset 0 -1px 0 rgba(255, 255, 255, 0.08);
}

.top-chrome > * {
  position: relative;
  pointer-events: auto;
}

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
  background: rgba(12, 15, 28, 0.42) !important;
  border: 1px solid rgba(255, 255, 255, 0.13) !important;
  box-shadow: 0 14px 34px rgba(0, 0, 0, 0.32), inset 0 1px 0 rgba(255, 255, 255, 0.1) !important;
}

.header-light {
  background: rgba(255, 255, 255, 0.46) !important;
  border: 1px solid rgba(255, 255, 255, 0.82) !important;
  box-shadow: 0 14px 34px rgba(80, 110, 170, 0.12), inset 0 1px 0 rgba(255, 255, 255, 0.92) !important;
}

.header-left {
  display: flex;
  align-items: center;
  gap: 12px;
}

.header-logo {
  width: 28px;
  height: 28px;
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

/* ── 主题三段切换器 ── */
.theme-switcher {
  display: inline-flex;
  align-items: center;
  gap: 2px;
  padding: 3px;
  border-radius: 10px;
  transition: background 0.25s ease, border-color 0.25s ease;
}

.switcher-dark {
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(255, 255, 255, 0.08);
}

.switcher-light {
  background: rgba(0, 0, 0, 0.04);
  border: 1px solid rgba(0, 0, 0, 0.06);
}

.theme-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 8px;
  border: none;
  cursor: pointer;
  font-family: inherit;
  transition: background 0.2s ease, color 0.2s ease, transform 0.15s ease, box-shadow 0.2s ease;
}

.theme-btn:hover  { transform: scale(1.06); }
.theme-btn:active { transform: scale(0.92); }

.theme-btn-active-dark {
  background: rgba(120, 100, 240, 0.6);
  color: rgba(255, 255, 255, 0.95);
  box-shadow: 0 2px 8px rgba(120, 100, 240, 0.4);
}

.theme-btn-active-light {
  background: rgba(255, 255, 255, 0.95);
  color: rgba(60, 60, 220, 0.9);
  box-shadow: 0 2px 6px rgba(60, 60, 220, 0.18);
}

.theme-btn-inactive-dark {
  background: transparent;
  color: rgba(255, 255, 255, 0.45);
}

.theme-btn-inactive-dark:hover {
  background: rgba(255, 255, 255, 0.08);
  color: rgba(255, 255, 255, 0.78);
}

.theme-btn-inactive-light {
  background: transparent;
  color: rgba(0, 0, 0, 0.42);
}

.theme-btn-inactive-light:hover {
  background: rgba(0, 0, 0, 0.05);
  color: rgba(0, 0, 0, 0.7);
}

/* ── Tab 导航 ── */
.app-nav {
  margin: 16px 24px 0;
  flex-shrink: 0;
}

.nav-inner {
  display: flex;
  justify-content: center;
  width: 100%;
  max-width: 960px;
  margin: 0 auto;
  padding-bottom: 16px;
}

.tab-group {
  --tab-gap: 6px;
  --tab-pad: 6px;
  display: inline-grid;
  grid-template-columns: repeat(4, minmax(108px, 1fr));
  gap: var(--tab-gap);
  padding: var(--tab-pad);
  position: relative;
  isolation: isolate;
  overflow: hidden;
  border-radius: 18px;
  backdrop-filter: blur(30px) saturate(1.7) contrast(1.04);
  -webkit-backdrop-filter: blur(30px) saturate(1.7) contrast(1.04);
}

.tab-slider {
  position: absolute;
  top: var(--tab-pad);
  bottom: var(--tab-pad);
  left: var(--tab-pad);
  z-index: 0;
  width: calc((100% - (var(--tab-pad) * 2) - (var(--tab-gap) * 3)) / 4);
  border-radius: 13px;
  pointer-events: none;
  overflow: hidden;
  transform: translateX(calc(var(--tab-index) * (100% + var(--tab-gap))));
  transition:
    transform 0.52s cubic-bezier(0.2, 1.18, 0.34, 1),
    filter 0.28s ease,
    box-shadow 0.28s ease;
  backdrop-filter: blur(18px) saturate(1.8) brightness(1.05);
  -webkit-backdrop-filter: blur(18px) saturate(1.8) brightness(1.05);
}

.tab-slider::before,
.tab-slider::after {
  content: '';
  position: absolute;
  inset: 0;
  pointer-events: none;
  border-radius: inherit;
}

.tab-slider::before {
  background:
    linear-gradient(135deg, rgba(255, 255, 255, 0.92), rgba(255, 255, 255, 0.34) 44%, rgba(118, 112, 255, 0.2)),
    radial-gradient(circle at 24% 8%, rgba(255, 255, 255, 0.9), transparent 30%),
    radial-gradient(circle at 78% 92%, rgba(92, 150, 255, 0.18), transparent 38%);
}

.tab-slider::after {
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.98),
    inset 0 -1px 0 rgba(255, 255, 255, 0.34),
    inset 10px 0 18px rgba(255, 255, 255, 0.2),
    inset -10px 0 22px rgba(92, 110, 220, 0.16);
}

.tab-group::before,
.tab-group::after {
  content: '';
  position: absolute;
  inset: 0;
  pointer-events: none;
  border-radius: inherit;
}

.tab-group::before {
  z-index: -2;
  background:
    linear-gradient(135deg, rgba(255, 255, 255, 0.5), rgba(255, 255, 255, 0.08) 42%, rgba(120, 150, 255, 0.12)),
    radial-gradient(circle at 18% 12%, rgba(255, 255, 255, 0.72), transparent 28%),
    radial-gradient(circle at 82% 86%, rgba(90, 170, 255, 0.16), transparent 34%);
}

.tab-group::after {
  z-index: -1;
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.78),
    inset 0 -1px 0 rgba(255, 255, 255, 0.24),
    inset 18px 0 28px rgba(255, 255, 255, 0.08),
    inset -18px 0 28px rgba(80, 120, 220, 0.08);
}

.tab-dark::before {
  background:
    linear-gradient(135deg, rgba(255, 255, 255, 0.12), rgba(255, 255, 255, 0.03) 44%, rgba(70, 110, 220, 0.12)),
    radial-gradient(circle at 18% 12%, rgba(255, 255, 255, 0.18), transparent 30%),
    radial-gradient(circle at 82% 86%, rgba(70, 190, 210, 0.12), transparent 38%);
}

.tab-dark::after {
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.18),
    inset 0 -1px 0 rgba(255, 255, 255, 0.06),
    inset 18px 0 28px rgba(255, 255, 255, 0.03),
    inset -18px 0 28px rgba(80, 120, 220, 0.06);
}

.tab-dark .tab-slider {
  backdrop-filter: blur(18px) saturate(1.65) brightness(1.08);
  -webkit-backdrop-filter: blur(18px) saturate(1.65) brightness(1.08);
  box-shadow: 0 10px 26px rgba(0, 0, 0, 0.34), 0 0 18px rgba(110, 94, 255, 0.16);
}

.tab-dark .tab-slider::before {
  background:
    linear-gradient(135deg, rgba(255, 255, 255, 0.18), rgba(255, 255, 255, 0.07) 42%, rgba(116, 102, 255, 0.26)),
    radial-gradient(circle at 24% 8%, rgba(255, 255, 255, 0.28), transparent 32%),
    radial-gradient(circle at 78% 92%, rgba(70, 190, 210, 0.16), transparent 38%);
}

.tab-dark .tab-slider::after {
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.28),
    inset 0 -1px 0 rgba(255, 255, 255, 0.08),
    inset 10px 0 18px rgba(255, 255, 255, 0.06),
    inset -10px 0 22px rgba(100, 120, 255, 0.14);
}

.tab-light .tab-slider {
  box-shadow: 0 10px 28px rgba(74, 90, 190, 0.16), 0 0 18px rgba(255, 255, 255, 0.46);
}

.tab-dark {
  background: rgba(18, 22, 38, 0.36) !important;
  border: 1px solid rgba(255, 255, 255, 0.16) !important;
  box-shadow: 0 14px 34px rgba(0, 0, 0, 0.28), 0 2px 8px rgba(255, 255, 255, 0.06) inset !important;
}

.tab-light {
  background: rgba(255, 255, 255, 0.42) !important;
  border: 1px solid rgba(255, 255, 255, 0.88) !important;
  box-shadow: 0 16px 42px rgba(80, 110, 170, 0.16), 0 2px 10px rgba(255, 255, 255, 0.7) inset !important;
}

.tab-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  padding: 7px 16px;
  min-width: 108px;
  border-radius: 10px;
  border: none;
  cursor: pointer;
  font-size: 13px;
  font-weight: 500;
  font-family: inherit;
  position: relative;
  z-index: 2;
  transition: background 0.2s ease, color 0.2s ease, transform 0.15s ease, box-shadow 0.2s ease;
}

.tab-btn:hover  { transform: scale(1.02); }
.tab-btn:active { transform: scale(0.97); }

.tab-icon { flex-shrink: 0; }

/* 激活态 – 暗色 */
.tab-active-dark {
  background: transparent;
  color: rgba(255, 255, 255, 0.95);
  box-shadow: none;
}

/* 激活态 – 亮色 */
.tab-active-light {
  background: transparent;
  color: rgba(60, 60, 220, 0.9);
  box-shadow: none;
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
  padding-top: 0;
}
</style>
