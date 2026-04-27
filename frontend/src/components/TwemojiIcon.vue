<script setup>
import { computed } from 'vue'
import twemoji from '@twemoji/api'
import lockWithKeySvg from '@twemoji/svg/1f510.svg'

const props = defineProps({
  emoji: {
    type: String,
    default: '',
  },
  codepoint: {
    type: String,
    default: '',
  },
  label: {
    type: String,
    default: '',
  },
  size: {
    type: [Number, String],
    default: 28,
  },
  decorative: {
    type: Boolean,
    default: false,
  },
})

const localSources = {
  '1f510': lockWithKeySvg,
}

const normalizedCodepoint = computed(() => {
  if (props.codepoint) return props.codepoint.toLowerCase()
  if (props.emoji) return twemoji.convert.toCodePoint(props.emoji)
  return ''
})

const emojiText = computed(() => {
  if (props.emoji) return props.emoji
  if (normalizedCodepoint.value) return twemoji.convert.fromCodePoint(normalizedCodepoint.value)
  return ''
})

const source = computed(() => {
  const codepoint = normalizedCodepoint.value
  if (!codepoint) return ''
  return localSources[codepoint] || `${twemoji.base}svg/${codepoint}${twemoji.ext.replace('.png', '.svg')}`
})

const iconSize = computed(() =>
  typeof props.size === 'number' ? `${props.size}px` : props.size
)

const altText = computed(() => {
  if (props.decorative) return ''
  return props.label || emojiText.value
})
</script>

<template>
  <img
    v-if="source"
    class="twemoji-icon"
    :src="source"
    :alt="altText"
    :title="decorative ? undefined : label || undefined"
    :aria-hidden="decorative ? 'true' : undefined"
    draggable="false"
  >
</template>

<style scoped>
.twemoji-icon {
  display: inline-block;
  width: v-bind(iconSize);
  height: v-bind(iconSize);
  flex: 0 0 auto;
  object-fit: contain;
  vertical-align: -0.12em;
}
</style>
