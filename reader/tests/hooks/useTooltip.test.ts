import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { renderHook, act } from '@testing-library/react'
import { useTooltip } from '@/hooks/useTooltip'
import type { Token } from '@/lib/types'

const sampleToken: Token = {
  id: 'token-1',
  position: 0,
  surface: '猫',
  base_form: '猫',
  reading: 'ネコ',
  pos: '名詞',
  sentence_text: '吾輩は猫である',
  is_interactive: true,
  word_entry_id: 'word-1',
}

const anotherToken: Token = {
  id: 'token-2',
  position: 5,
  surface: '走る',
  base_form: '走る',
  reading: 'ハシル',
  pos: '動詞',
  sentence_text: '猫が走る',
  is_interactive: true,
  word_entry_id: 'word-2',
}

describe('useTooltip', () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('初期状態は閉じている', () => {
    const { result } = renderHook(() => useTooltip())

    expect(result.current.isOpen).toBe(false)
    expect(result.current.activeToken).toBeNull()
  })

  it('open() で tooltip を開ける', () => {
    const { result } = renderHook(() => useTooltip())

    act(() => {
      result.current.open(sampleToken)
    })

    expect(result.current.isOpen).toBe(true)
    expect(result.current.activeToken).toEqual(sampleToken)
  })

  it('close() で tooltip を閉じる', () => {
    const { result } = renderHook(() => useTooltip())

    act(() => {
      result.current.open(sampleToken)
    })
    expect(result.current.isOpen).toBe(true)

    act(() => {
      result.current.close()
    })
    expect(result.current.isOpen).toBe(false)
    expect(result.current.activeToken).toBeNull()
  })

  it('別の token を open すると activeToken が切り替わる', () => {
    const { result } = renderHook(() => useTooltip())

    act(() => {
      result.current.open(sampleToken)
    })
    expect(result.current.activeToken?.id).toBe('token-1')

    act(() => {
      result.current.open(anotherToken)
    })
    expect(result.current.activeToken?.id).toBe('token-2')
    expect(result.current.isOpen).toBe(true)
  })

  // T040: Two-tier trigger strategy
  it('getTrigger: unknown → click, known → hover', () => {
    const { result } = renderHook(() => useTooltip())

    expect(result.current.getTrigger('unknown')).toBe('click')
    expect(result.current.getTrigger('new')).toBe('hover')
    expect(result.current.getTrigger('learning')).toBe('hover')
    expect(result.current.getTrigger('known')).toBe('hover')
  })

  it('handleMouseEnter: known word で即時 open', () => {
    const { result } = renderHook(() => useTooltip())

    act(() => {
      result.current.handleMouseEnter(sampleToken, 'learning')
    })

    expect(result.current.isOpen).toBe(true)
    expect(result.current.activeToken).toEqual(sampleToken)
  })

  it('handleMouseEnter: unknown word では open しない', () => {
    const { result } = renderHook(() => useTooltip())

    act(() => {
      result.current.handleMouseEnter(sampleToken, 'unknown')
    })

    expect(result.current.isOpen).toBe(false)
  })

  // T043: safePolygon grace period
  it('handleMouseLeave: 300ms 後に close', () => {
    const { result } = renderHook(() => useTooltip())

    act(() => {
      result.current.open(sampleToken)
    })
    expect(result.current.isOpen).toBe(true)

    act(() => {
      result.current.handleMouseLeave()
    })
    // Still open during grace period
    expect(result.current.isOpen).toBe(true)

    // After 300ms, should close
    act(() => {
      vi.advanceTimersByTime(300)
    })
    expect(result.current.isOpen).toBe(false)
  })

  it('handleMouseLeave → 再 open: grace period をキャンセル', () => {
    const { result } = renderHook(() => useTooltip())

    act(() => {
      result.current.open(sampleToken)
    })

    act(() => {
      result.current.handleMouseLeave()
    })

    // Re-open before grace period expires
    act(() => {
      vi.advanceTimersByTime(100)
      result.current.open(anotherToken)
    })

    // After original grace period
    act(() => {
      vi.advanceTimersByTime(300)
    })
    // Should still be open (grace period was cancelled by re-open)
    expect(result.current.isOpen).toBe(true)
    expect(result.current.activeToken?.id).toBe('token-2')
  })
})
