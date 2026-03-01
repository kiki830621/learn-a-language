"use client";

import { useEffect } from "react";
import { TokenSpan } from "@/components/TokenSpan";
import { Tooltip } from "@/components/Tooltip";
import { useTooltip } from "@/hooks/useTooltip";
import { useUserVocabulary } from "@/hooks/useUserVocabulary";
import type { Token } from "@/lib/types";

type ReadingViewProps = {
  readonly tokens: Token[];
  readonly scrollToPosition?: number;
};

/**
 * 閱讀區域的 Client Component wrapper
 *
 * Server Component (ReadingPage) から tokens を受け取り、
 * useTooltip と useUserVocabulary フックで状態を管理する。
 *
 * US2: 既知の単語は hover で即時 tooltip、未知は click でトリガー。
 * TokenSpan に vocabStatus を渡して underline 表示を制御。
 */
export function ReadingView({ tokens, scrollToPosition }: ReadingViewProps) {
  const {
    isOpen,
    activeToken,
    open,
    close,
    handleMouseEnter,
    handleMouseLeave,
  } = useTooltip();
  const { getStatus, getExposureCount, markAsKnown, resetToLearning } =
    useUserVocabulary();

  useEffect(() => {
    if (scrollToPosition === undefined) return;
    const el = document.querySelector(`[data-position="${scrollToPosition}"]`);
    el?.scrollIntoView({ behavior: "smooth", block: "center" });
  }, [scrollToPosition]);

  return (
    <div className="token-flow">
      {tokens.map((token) => {
        const vocabStatus = token.word_entry_id
          ? getStatus(token.word_entry_id)
          : "unknown";

        const exposureCount = token.word_entry_id
          ? getExposureCount(token.word_entry_id)
          : 0;

        return (
          <TokenSpan
            key={token.id}
            token={token}
            vocabStatus={vocabStatus}
            exposureCount={exposureCount}
            onClick={open}
            onMouseEnter={(t) => handleMouseEnter(t, vocabStatus)}
            onMouseLeave={handleMouseLeave}
          />
        );
      })}
      {activeToken && (
        <Tooltip
          token={activeToken}
          isOpen={isOpen}
          vocabStatus={
            activeToken.word_entry_id
              ? getStatus(activeToken.word_entry_id)
              : "unknown"
          }
          onClose={close}
          onMarkAsKnown={markAsKnown}
          onResetToLearning={resetToLearning}
        />
      )}
    </div>
  );
}
