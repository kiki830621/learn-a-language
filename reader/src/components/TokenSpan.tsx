"use client";

import type { Token, VocabStatus } from "@/lib/types";

type TokenSpanProps = {
  readonly token: Token;
  readonly vocabStatus?: VocabStatus;
  readonly exposureCount?: number;
  readonly onClick?: (token: Token) => void;
  readonly onMouseEnter?: (token: Token) => void;
  readonly onMouseLeave?: () => void;
};

/**
 * 單一 Token 渲染元件
 *
 * 互動式 token 渲染為可點擊的 button：
 * - US1: 基本的 click/tap 觸發 tooltip
 * - US2: vocabStatus 決定 hover 行為和底線樣式
 *   - new/learning → 顯示底線（提示已查過）
 *   - known → 不顯示底線（已掌握）
 *   - unknown → 無底線（還沒查過）
 * - US4: exposureCount 決定底線強度
 *   - 1-2: vocab-underline-light（淡色）
 *   - 3-4: vocab-underline-dark（深色）
 *   - 5+: 無底線（已卒業）
 */
export function TokenSpan({
  token,
  vocabStatus = "unknown",
  exposureCount = 0,
  onClick,
  onMouseEnter,
  onMouseLeave,
}: TokenSpanProps) {
  if (token.is_interactive) {
    const classNames = ["token-span", "interactive"];
    if (
      (vocabStatus === "new" || vocabStatus === "learning") &&
      exposureCount < 5
    ) {
      if (exposureCount >= 3) {
        classNames.push("vocab-underline-dark");
      } else {
        classNames.push("vocab-underline-light");
      }
    }

    return (
      <button
        type="button"
        className={classNames.join(" ")}
        onClick={() => onClick?.(token)}
        onMouseEnter={() => onMouseEnter?.(token)}
        onMouseLeave={() => onMouseLeave?.()}
        data-vocab-status={vocabStatus}
        data-position={token.position}
      >
        {token.surface}
      </button>
    );
  }

  return (
    <span className="token-span" data-position={token.position}>
      {token.surface}
    </span>
  );
}
