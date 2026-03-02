"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import {
  useFloating,
  useClick,
  useDismiss,
  useInteractions,
  offset,
  flip,
  shift,
  FloatingPortal,
  FloatingFocusManager,
} from "@floating-ui/react";
import { createBrowserSupabase } from "@/lib/supabase-browser";
import type {
  Token,
  WordEntry,
  CrossTextExample,
  VocabStatus,
} from "@/lib/types";

type TooltipProps = {
  readonly token: Token;
  readonly isOpen: boolean;
  readonly vocabStatus?: VocabStatus;
  readonly onClose: () => void;
  readonly onMarkAsKnown?: (wordEntryId: string) => void;
  readonly onResetToLearning?: (wordEntryId: string) => void;
};

/**
 * Tooltip 元件
 *
 * 使用 Floating UI 定位，根據 POS 策略顯示不同內容：
 * - 名詞（definition 策略）：讀音 + POS + 辭書定義
 * - 動詞/形容詞（examples 策略）：讀音 + POS + AI 解説 + 他の作品での用例
 */
export function Tooltip({
  token,
  isOpen,
  vocabStatus = "unknown",
  onClose,
  onMarkAsKnown,
  onResetToLearning,
}: TooltipProps) {
  const [wordEntry, setWordEntry] = useState<WordEntry | null>(null);
  const [crossTextExamples, setCrossTextExamples] = useState<
    CrossTextExample[]
  >([]);
  const [loading, setLoading] = useState(false);

  const { refs, floatingStyles, context } = useFloating({
    open: isOpen,
    onOpenChange: (open) => {
      if (!open) onClose();
    },
    middleware: [offset(8), flip(), shift({ padding: 8 })],
  });

  const click = useClick(context);
  const dismiss = useDismiss(context);
  const { getReferenceProps, getFloatingProps } = useInteractions([
    click,
    dismiss,
  ]);

  // Fetch word entry when tooltip opens
  useEffect(() => {
    if (!isOpen || !token.word_entry_id) {
      setWordEntry(null);
      setLoading(false);
      return;
    }

    let cancelled = false;
    setLoading(true);

    const supabase = createBrowserSupabase();

    // Fire-and-forget: record word lookup (T035)
    supabase
      .rpc("record_word_lookup", { p_word_entry_id: token.word_entry_id })
      .then(() => {
        // Intentionally fire-and-forget
      });

    // Q3: Fetch word entry (BCNF — no cross_text_examples / work_count)
    supabase
      .from("word_entries")
      .select("id, base_form, pos, reading, ai_explanation")
      .eq("id", token.word_entry_id)
      .single()
      .then(({ data, error }) => {
        if (cancelled) return;
        if (error) {
          setLoading(false);
          return;
        }
        setWordEntry(data as WordEntry);
        setLoading(false);

        // Fetch cross-text examples (BCNF: separate table with JOINs)
        supabase
          .from("cross_text_examples")
          .select(
            "work_id, token_position, works(title, author), sentences(text)",
          )
          .eq("word_entry_id", token.word_entry_id!)
          .then(({ data: exData }) => {
            if (cancelled) return;
            if (exData && exData.length > 0) {
              const examples: CrossTextExample[] = exData.map((row: any) => ({
                work_id: row.work_id,
                work_title: (row.works as any)?.title ?? "",
                author: (row.works as any)?.author ?? "",
                sentence: (row.sentences as any)?.text ?? "",
                token_position: row.token_position,
              }));
              setCrossTextExamples(examples);
            }
          });
      });

    return () => {
      cancelled = true;
    };
  }, [isOpen, token.word_entry_id]);

  if (!isOpen) return null;

  // No word_entry_id — show fallback
  if (!token.word_entry_id) {
    return (
      <FloatingPortal>
        <div
          ref={refs.setFloating}
          style={floatingStyles}
          className="tooltip-panel"
          {...getFloatingProps()}
        >
          <div className="tooltip-header">
            <span className="tooltip-no-data">辞書データがありません</span>
            <button
              type="button"
              className="tooltip-close"
              onClick={onClose}
              aria-label="閉じる"
            >
              ×
            </button>
          </div>
        </div>
      </FloatingPortal>
    );
  }

  return (
    <FloatingPortal>
      <FloatingFocusManager context={context} modal={false}>
        <div
          ref={refs.setFloating}
          style={floatingStyles}
          className="tooltip-panel"
          {...getFloatingProps()}
        >
          {loading ? (
            <div className="tooltip-loading">読み込み中...</div>
          ) : wordEntry ? (
            <TooltipContent
              wordEntry={wordEntry}
              crossTextExamples={crossTextExamples}
              vocabStatus={vocabStatus}
              onClose={onClose}
              onMarkAsKnown={onMarkAsKnown}
              onResetToLearning={onResetToLearning}
            />
          ) : (
            <div className="tooltip-error">
              <span>データの取得に失敗しました</span>
              <button
                type="button"
                className="tooltip-close"
                onClick={onClose}
                aria-label="閉じる"
              >
                ×
              </button>
            </div>
          )}
        </div>
      </FloatingFocusManager>
    </FloatingPortal>
  );
}

type TooltipContentProps = {
  readonly wordEntry: WordEntry;
  readonly crossTextExamples: CrossTextExample[];
  readonly vocabStatus: VocabStatus;
  readonly onClose: () => void;
  readonly onMarkAsKnown?: (wordEntryId: string) => void;
  readonly onResetToLearning?: (wordEntryId: string) => void;
};

function TooltipContent({
  wordEntry,
  crossTextExamples,
  vocabStatus,
  onClose,
  onMarkAsKnown,
  onResetToLearning,
}: TooltipContentProps) {
  return (
    <>
      <div className="tooltip-header">
        <div className="tooltip-word-info">
          <span className="tooltip-reading">{wordEntry.reading}</span>
          <span className="tooltip-pos">{wordEntry.pos}</span>
        </div>
        <button
          type="button"
          className="tooltip-close"
          onClick={onClose}
          aria-label="閉じる"
        >
          ×
        </button>
      </div>

      <div className="tooltip-body">
        {wordEntry.ai_explanation && (
          <p className="tooltip-ai-explanation">{wordEntry.ai_explanation}</p>
        )}

        {crossTextExamples.length > 0 && (
          <div className="tooltip-cross-text">
            <h4>他の作品での用例</h4>
            <ul>
              {crossTextExamples.map((example: CrossTextExample) => (
                <li key={`${example.work_id}-${example.token_position}`}>
                  <Link
                    href={`/works/${example.work_id}?position=${example.token_position}`}
                    className="tooltip-example-link"
                  >
                    <span className="tooltip-example-sentence">
                      {example.sentence}
                    </span>
                    <span className="tooltip-example-source">
                      — {example.work_title}（{example.author}）
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>

      {/* T044: Manual override buttons (FR-015) */}
      {vocabStatus !== "unknown" && (
        <div className="tooltip-actions">
          {vocabStatus !== "known" ? (
            <button
              type="button"
              className="tooltip-action-btn"
              onClick={() => onMarkAsKnown?.(wordEntry.id)}
            >
              ✓ 覚えた
            </button>
          ) : (
            <button
              type="button"
              className="tooltip-action-btn"
              onClick={() => onResetToLearning?.(wordEntry.id)}
            >
              ↻ 学習中に戻す
            </button>
          )}
        </div>
      )}
    </>
  );
}
