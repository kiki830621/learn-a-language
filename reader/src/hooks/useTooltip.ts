'use client'

import { useState, useCallback, useRef } from 'react'
import type { Token, VocabStatus } from '@/lib/types'

type TooltipTrigger = 'click' | 'hover'

type UseTooltipReturn = {
  isOpen: boolean
  activeToken: Token | null
  open: (token: Token) => void
  close: () => void
  getTrigger: (vocabStatus: VocabStatus) => TooltipTrigger
  handleMouseEnter: (token: Token, vocabStatus: VocabStatus) => void
  handleMouseLeave: () => void
}

/**
 * Tooltip の開閉状態を管理するフック
 *
 * US2: Two-tier hover behavior
 * - 既知の単語（new/learning/known）→ hover で即時表示
 * - 未知の単語 → click でトリガー
 *
 * T043: safePolygon — マウスが離れても 300ms の猶予期間で
 * tooltip まで移動する時間を確保する。
 */
export function useTooltip(): UseTooltipReturn {
  const [activeToken, setActiveToken] = useState<Token | null>(null)
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const cancelPendingClose = useCallback(() => {
    if (timeoutRef.current !== null) {
      clearTimeout(timeoutRef.current)
      timeoutRef.current = null
    }
  }, [])

  const open = useCallback((token: Token) => {
    cancelPendingClose()
    setActiveToken(token)
  }, [cancelPendingClose])

  const close = useCallback(() => {
    cancelPendingClose()
    setActiveToken(null)
  }, [cancelPendingClose])

  const getTrigger = useCallback(
    (vocabStatus: VocabStatus): TooltipTrigger => {
      return vocabStatus === 'unknown' ? 'click' : 'hover'
    },
    []
  )

  // T040: Mouse enter — known words open instantly
  const handleMouseEnter = useCallback(
    (token: Token, vocabStatus: VocabStatus) => {
      if (vocabStatus === 'unknown') return
      cancelPendingClose()
      setActiveToken(token)
    },
    [cancelPendingClose]
  )

  // T043: Mouse leave with grace period (~300ms)
  const handleMouseLeave = useCallback(() => {
    timeoutRef.current = setTimeout(() => {
      setActiveToken(null)
      timeoutRef.current = null
    }, 300)
  }, [])

  return {
    isOpen: activeToken !== null,
    activeToken,
    open,
    close,
    getTrigger,
    handleMouseEnter,
    handleMouseLeave,
  }
}
