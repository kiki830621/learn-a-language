import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import { WorkList } from '@/components/WorkList'
import type { WorkListItem } from '@/lib/types'

// Mock supabase-browser 模組
const mockSelect = vi.fn()
const mockOrder = vi.fn()
const mockFrom = vi.fn()

vi.mock('@/lib/supabase-browser', () => ({
  createBrowserSupabase: () => ({
    from: mockFrom,
  }),
}))

const sampleWorks: WorkListItem[] = [
  {
    id: 'work-1',
    title: '吾輩は猫である',
    author: '夏目漱石',
    publish_year: 1905,
    token_count: 12000,
    processed_at: '2026-01-01T00:00:00Z',
  },
  {
    id: 'work-2',
    title: '羅生門',
    author: '芥川龍之介',
    publish_year: 1915,
    token_count: 3500,
    processed_at: '2026-01-02T00:00:00Z',
  },
]

describe('WorkList', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockOrder.mockResolvedValue({ data: sampleWorks, error: null })
    mockSelect.mockReturnValue({ order: mockOrder })
    mockFrom.mockReturnValue({ select: mockSelect })
  })

  it('渲染作品標題和作者', async () => {
    const ui = await WorkList()
    render(ui)

    expect(screen.getByText('吾輩は猫である')).toBeInTheDocument()
    expect(screen.getByText('夏目漱石')).toBeInTheDocument()
    expect(screen.getByText('羅生門')).toBeInTheDocument()
    expect(screen.getByText('芥川龍之介')).toBeInTheDocument()
  })

  it('每個作品都有連結到 /works/[id]', async () => {
    const ui = await WorkList()
    render(ui)

    const links = screen.getAllByRole('link')
    expect(links).toHaveLength(2)
    expect(links[0]).toHaveAttribute('href', '/works/work-1')
    expect(links[1]).toHaveAttribute('href', '/works/work-2')
  })

  it('沒有作品時顯示空狀態', async () => {
    mockOrder.mockResolvedValue({ data: [], error: null })

    const ui = await WorkList()
    render(ui)

    expect(screen.getByText('まだ作品がありません')).toBeInTheDocument()
  })

  it('呼叫正確的 Supabase 查詢', async () => {
    await WorkList()

    expect(mockFrom).toHaveBeenCalledWith('works')
    expect(mockSelect).toHaveBeenCalledWith(
      'id, title, author, publish_year, token_count, processed_at'
    )
    expect(mockOrder).toHaveBeenCalledWith('publish_year', { ascending: true })
  })
})
