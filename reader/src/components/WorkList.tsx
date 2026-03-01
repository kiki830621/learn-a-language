import Link from 'next/link'
import { createBrowserSupabase } from '@/lib/supabase-browser'
import type { WorkListItem } from '@/lib/types'

/**
 * 作品清單元件（Q1 查詢）
 * 從 Supabase 取得所有作品，以清單形式呈現。
 * 每個作品附帶連結至 /works/[id] 閱讀頁。
 */
export async function WorkList() {
  const supabase = createBrowserSupabase()

  const { data: works, error } = await supabase
    .from('works')
    .select('id, title, author, publish_year, token_count, processed_at')
    .order('publish_year', { ascending: true })

  if (error) {
    return <p className="error">作品の読み込みに失敗しました</p>
  }

  const items = (works ?? []) as WorkListItem[]

  if (items.length === 0) {
    return <p className="empty-state">まだ作品がありません</p>
  }

  return (
    <ul className="work-list">
      {items.map((work) => (
        <li key={work.id} className="work-list-item">
          <Link href={`/works/${work.id}`}>
            <span className="work-title">{work.title}</span>
            <span className="work-author">{work.author}</span>
            {work.publish_year && (
              <span className="work-year">{work.publish_year}</span>
            )}
            <span className="work-token-count">
              {work.token_count.toLocaleString()} tokens
            </span>
          </Link>
        </li>
      ))}
    </ul>
  )
}
