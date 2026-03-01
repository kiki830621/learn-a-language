import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, act, waitFor } from '@testing-library/react'
import { useUserVocabulary } from '@/hooks/useUserVocabulary'
import type { UserVocabRecord } from '@/lib/types'

// Mock supabase-browser
const mockSelect = vi.fn()
const mockFrom = vi.fn()
const mockEq = vi.fn()
const mockUpdate = vi.fn()

vi.mock('@/lib/supabase-browser', () => ({
  createBrowserSupabase: () => ({
    from: mockFrom,
  }),
}))

const vocabRecords: UserVocabRecord[] = [
  { word_entry_id: 'word-1', exposure_count: 3, status: 'learning' },
  { word_entry_id: 'word-2', exposure_count: 1, status: 'new' },
  { word_entry_id: 'word-3', exposure_count: 8, status: 'known' },
]

describe('useUserVocabulary', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    // Q4: Fetch all user vocabulary
    mockSelect.mockResolvedValue({ data: vocabRecords, error: null })
    mockFrom.mockReturnValue({ select: mockSelect })
  })

  it('從 Supabase 取得使用者的詞彙記錄', async () => {
    const { result } = renderHook(() => useUserVocabulary())

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    expect(mockFrom).toHaveBeenCalledWith('user_vocabulary')
    expect(mockSelect).toHaveBeenCalledWith('word_entry_id, exposure_count, status')
  })

  it('提供 vocabMap 快速查詢', async () => {
    const { result } = renderHook(() => useUserVocabulary())

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    const map = result.current.vocabMap
    expect(map.get('word-1')).toEqual(vocabRecords[0])
    expect(map.get('word-2')).toEqual(vocabRecords[1])
    expect(map.get('word-3')).toEqual(vocabRecords[2])
    expect(map.get('word-not-exist')).toBeUndefined()
  })

  it('getStatus 回傳正確的 VocabStatus', async () => {
    const { result } = renderHook(() => useUserVocabulary())

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    expect(result.current.getStatus('word-1')).toBe('learning')
    expect(result.current.getStatus('word-2')).toBe('new')
    expect(result.current.getStatus('word-3')).toBe('known')
    expect(result.current.getStatus('unknown-word')).toBe('unknown')
  })

  it('markAsKnown 執行 M2 mutation 並樂觀更新', async () => {
    // Setup M2 mock
    const mockUpdateSelect = vi.fn().mockResolvedValue({
      data: [{ word_entry_id: 'word-1', exposure_count: 3, status: 'known' }],
      error: null,
    })
    const mockUpdateEq = vi.fn().mockReturnValue({ select: mockUpdateSelect })
    mockUpdate.mockReturnValue({ eq: mockUpdateEq })

    // Override mockFrom for chained calls
    mockFrom.mockImplementation((table: string) => {
      if (table === 'user_vocabulary') {
        return {
          select: mockSelect,
          update: mockUpdate,
        }
      }
      return { select: mockSelect }
    })

    const { result } = renderHook(() => useUserVocabulary())

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    // Optimistic: should immediately update
    act(() => {
      result.current.markAsKnown('word-1')
    })

    expect(result.current.getStatus('word-1')).toBe('known')
  })

  it('resetToLearning 執行 M3 mutation 並樂觀更新', async () => {
    const mockUpdateSelect = vi.fn().mockResolvedValue({
      data: [{ word_entry_id: 'word-3', exposure_count: 0, status: 'learning' }],
      error: null,
    })
    const mockUpdateEq = vi.fn().mockReturnValue({ select: mockUpdateSelect })
    mockUpdate.mockReturnValue({ eq: mockUpdateEq })

    mockFrom.mockImplementation((table: string) => {
      if (table === 'user_vocabulary') {
        return {
          select: mockSelect,
          update: mockUpdate,
        }
      }
      return { select: mockSelect }
    })

    const { result } = renderHook(() => useUserVocabulary())

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false)
    })

    act(() => {
      result.current.resetToLearning('word-3')
    })

    expect(result.current.getStatus('word-3')).toBe('learning')
  })

  it('loading 初始狀態為 true', () => {
    // Never resolve to keep loading
    mockSelect.mockReturnValue(new Promise(() => {}))

    const { result } = renderHook(() => useUserVocabulary())

    expect(result.current.isLoading).toBe(true)
    expect(result.current.vocabMap.size).toBe(0)
  })
})
