import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { Tooltip } from "@/components/Tooltip";
import type { Token, WordEntry } from "@/lib/types";

// Mock Floating UI — provide minimal implementations
vi.mock("@floating-ui/react", () => ({
  useFloating: () => ({
    refs: {
      setReference: vi.fn(),
      setFloating: vi.fn(),
      reference: { current: null },
      floating: { current: null },
    },
    floatingStyles: { position: "absolute" as const, top: 0, left: 0 },
    context: {
      open: true,
      onOpenChange: vi.fn(),
      refs: {
        reference: { current: null },
        floating: { current: null },
        domReference: { current: null },
      },
      elements: { reference: null, floating: null },
      dataRef: { current: {} },
      nodeId: undefined,
      floatingId: "floating-1",
      events: { on: vi.fn(), off: vi.fn(), emit: vi.fn() },
    },
  }),
  useClick: () => ({}),
  useDismiss: () => ({}),
  useInteractions: () => ({
    getReferenceProps: () => ({}),
    getFloatingProps: () => ({}),
  }),
  offset: () => ({}),
  flip: () => ({}),
  shift: () => ({}),
  autoUpdate: vi.fn(),
  FloatingPortal: ({ children }: { children: React.ReactNode }) => (
    <div data-testid="floating-portal">{children}</div>
  ),
  FloatingFocusManager: ({ children }: { children: React.ReactNode }) => (
    <>{children}</>
  ),
}));

// Mock supabase-browser
const mockRpc = vi.fn();
const mockSingle = vi.fn();
const mockEq = vi.fn();
const mockSelect = vi.fn();
const mockFrom = vi.fn();
// BCNF: separate mock for cross_text_examples query
const mockCrossTextEq = vi.fn();

vi.mock("@/lib/supabase-browser", () => ({
  createBrowserSupabase: () => ({
    from: mockFrom,
    rpc: mockRpc,
  }),
}));

const nounToken: Token = {
  id: "token-noun",
  position: 0,
  surface: "猫",
  is_interactive: true,
  word_entry_id: "word-1",
  sentence_id: "sent-1",
};

const verbToken: Token = {
  id: "token-verb",
  position: 5,
  surface: "走る",
  is_interactive: true,
  word_entry_id: "word-2",
  sentence_id: "sent-2",
};

const nounWordEntry: WordEntry = {
  id: "word-1",
  base_form: "猫",
  pos: "名詞",
  reading: "ネコ",
  jmdict_def: "cat; puss; kitty",
  ai_explanation: null,
};

const verbWordEntry: WordEntry = {
  id: "word-2",
  base_form: "走る",
  pos: "動詞",
  reading: "ハシル",
  jmdict_def: "to run",
  ai_explanation: "「走る」は移動を表す基本的な動詞です。",
};

describe("Tooltip", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Default: word entry fetch succeeds (word_entries table)
    mockSingle.mockResolvedValue({ data: nounWordEntry, error: null });
    mockEq.mockReturnValue({ single: mockSingle });
    mockSelect.mockReturnValue({ eq: mockEq });
    // Default: cross-text examples empty (cross_text_examples table)
    mockCrossTextEq.mockResolvedValue({ data: [], error: null });
    // BCNF: mockFrom dispatches by table name
    mockFrom.mockImplementation((table: string) => {
      if (table === "cross_text_examples") {
        return {
          select: vi.fn().mockReturnValue({ eq: mockCrossTextEq }),
        };
      }
      return { select: mockSelect }; // word_entries
    });
    // Default: rpc succeeds
    mockRpc.mockResolvedValue({ data: null, error: null });
  });

  it("表示 reading（振り仮名）", async () => {
    render(<Tooltip token={nounToken} isOpen={true} onClose={vi.fn()} />);

    await waitFor(() => {
      expect(screen.getByText("ネコ")).toBeInTheDocument();
    });
  });

  it("名詞の場合、定義セクションを表示する", async () => {
    render(<Tooltip token={nounToken} isOpen={true} onClose={vi.fn()} />);

    await waitFor(() => {
      expect(screen.getByText("ネコ")).toBeInTheDocument();
      expect(screen.getByText("cat; puss; kitty")).toBeInTheDocument();
    });
  });

  it("動詞の場合、AI 説明と用例セクションを表示する", async () => {
    mockSingle.mockResolvedValue({ data: verbWordEntry, error: null });
    // BCNF: cross-text examples from separate table (PostgREST embedded resources)
    mockCrossTextEq.mockResolvedValue({
      data: [
        {
          work_id: "work-1",
          token_position: 2,
          works: { title: "吾輩は猫である", author: "夏目漱石" },
          sentences: { text: "猫が走る" },
        },
      ],
      error: null,
    });

    render(<Tooltip token={verbToken} isOpen={true} onClose={vi.fn()} />);

    await waitFor(() => {
      expect(screen.getByText("ハシル")).toBeInTheDocument();
      expect(
        screen.getByText("「走る」は移動を表す基本的な動詞です。"),
      ).toBeInTheDocument();
      // Should show cross-text examples section
      expect(screen.getByText("他の作品での用例")).toBeInTheDocument();
      expect(screen.getByText("猫が走る")).toBeInTheDocument();
    });
  });

  it("POS タグを表示する", async () => {
    render(<Tooltip token={nounToken} isOpen={true} onClose={vi.fn()} />);

    await waitFor(() => {
      expect(screen.getByText("名詞")).toBeInTheDocument();
    });
  });

  it("閉じるボタンが機能する", async () => {
    const handleClose = vi.fn();

    render(<Tooltip token={nounToken} isOpen={true} onClose={handleClose} />);

    await waitFor(() => {
      expect(screen.getByText("ネコ")).toBeInTheDocument();
    });

    const closeButton = screen.getByRole("button", { name: /閉じる/ });
    fireEvent.click(closeButton);
    expect(handleClose).toHaveBeenCalledOnce();
  });

  it("isOpen が false の場合、tooltip を表示しない", () => {
    render(<Tooltip token={nounToken} isOpen={false} onClose={vi.fn()} />);

    expect(screen.queryByText("ネコ")).toBeNull();
  });

  it("loading 中はローディング表示する", () => {
    // Make the fetch never resolve to keep loading state
    mockSingle.mockReturnValue(new Promise(() => {}));
    mockEq.mockReturnValue({ single: mockSingle });
    mockSelect.mockReturnValue({ eq: mockEq });
    mockFrom.mockReturnValue({ select: mockSelect });

    render(<Tooltip token={nounToken} isOpen={true} onClose={vi.fn()} />);

    expect(screen.getByText("読み込み中...")).toBeInTheDocument();
  });

  it("tooltip が開いた時に record_word_lookup を呼び出す", async () => {
    render(<Tooltip token={nounToken} isOpen={true} onClose={vi.fn()} />);

    await waitFor(() => {
      expect(mockRpc).toHaveBeenCalledWith("record_word_lookup", {
        p_word_entry_id: "word-1",
      });
    });
  });

  it("word_entry_id が null の場合、fetch を呼び出さない", () => {
    const tokenNoEntry: Token = {
      ...nounToken,
      word_entry_id: null,
    };

    render(<Tooltip token={tokenNoEntry} isOpen={true} onClose={vi.fn()} />);

    expect(mockFrom).not.toHaveBeenCalled();
    expect(screen.getByText("辞書データがありません")).toBeInTheDocument();
  });
});
