"use client";

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <main className="reading-container">
      <div className="error">
        <p>エラーが発生しました</p>
        <p style={{ fontSize: "0.85rem", marginTop: "0.5rem" }}>
          {error.message || "予期しないエラーです"}
        </p>
        <button
          type="button"
          onClick={reset}
          className="tooltip-action-btn"
          style={{ marginTop: "1rem" }}
        >
          もう一度試す
        </button>
      </div>
    </main>
  );
}
