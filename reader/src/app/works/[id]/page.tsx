import Link from "next/link";
import { unstable_cache } from "next/cache";
import { createServerSupabase } from "@/lib/supabase";
import { ReadingView } from "@/components/ReadingView";
import type { Token, WorkListItem } from "@/lib/types";

type ReadingPageProps = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ position?: string }>;
};

// T057: Cache token queries for 24 hours (static content, rarely changes)
const getWorkData = unstable_cache(
  async (id: string) => {
    const supabase = createServerSupabase();

    const [workResult, tokensResult] = await Promise.all([
      supabase
        .from("works")
        .select("id, title, author, publish_year, token_count, processed_at")
        .eq("id", id)
        .single(),
      supabase
        .from("tokens")
        .select(
          "id, position, surface, is_interactive, word_entry_id, sentence_id",
        )
        .eq("work_id", id)
        .order("position", { ascending: true }),
    ]);

    return {
      work: workResult.data as WorkListItem | null,
      tokens: (tokensResult.data ?? []) as Token[],
    };
  },
  ["work-data"],
  { revalidate: 86400 },
);

/**
 * 作品閱讀ページ（Server Component）
 * Q2 查詢：取得某作品的全部 tokens，以 ReadingView (Client) 渲染。
 * ReadingView 內部管理 TokenSpan + Tooltip 的互動。
 */
export default async function ReadingPage({
  params,
  searchParams,
}: ReadingPageProps) {
  const { id } = await params;
  const { position } = await searchParams;
  const scrollToPosition =
    position !== undefined ? Number(position) : undefined;

  const { work, tokens } = await getWorkData(id);

  if (!work) {
    return (
      <main className="reading-container">
        <Link href="/" className="back-link">
          ← 作品一覧に戻る
        </Link>
        <p className="error">作品が見つかりませんでした</p>
      </main>
    );
  }

  return (
    <main className="reading-container">
      <Link href="/" className="back-link">
        ← 作品一覧に戻る
      </Link>
      <header className="work-header">
        <h1>{work.title}</h1>
        <p className="author">{work.author}</p>
      </header>
      <ReadingView tokens={tokens} scrollToPosition={scrollToPosition} />
    </main>
  );
}
