import { WorkList } from '@/components/WorkList'

/**
 * 作品一覧ページ（Server Component）
 * Q1 查詢：取得所有作品清單
 */
export default function HomePage() {
  return (
    <main>
      <h1 className="page-title">作品一覧</h1>
      <WorkList />
    </main>
  )
}
