import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { TokenSpan } from "@/components/TokenSpan";
import type { Token } from "@/lib/types";

const baseToken: Token = {
  id: "token-1",
  position: 0,
  surface: "猫",
  is_interactive: true,
  word_entry_id: "word-1",
  sentence_id: "sent-1",
};

describe("TokenSpan", () => {
  it("渲染 token 的 surface 文字", () => {
    render(<TokenSpan token={baseToken} />);

    expect(screen.getByText("猫")).toBeInTheDocument();
  });

  it("互動式 token 渲染為 button", () => {
    render(<TokenSpan token={baseToken} />);

    const button = screen.getByRole("button");
    expect(button).toBeInTheDocument();
    expect(button).toHaveTextContent("猫");
  });

  it("互動式 token 可以點擊並觸發 onClick", () => {
    const handleClick = vi.fn();
    render(<TokenSpan token={baseToken} onClick={handleClick} />);

    fireEvent.click(screen.getByRole("button"));
    expect(handleClick).toHaveBeenCalledWith(baseToken);
  });

  it("互動式 token 有 hover 樣式的 className", () => {
    render(<TokenSpan token={baseToken} />);

    const button = screen.getByRole("button");
    expect(button.className).toContain("interactive");
  });

  it("非互動式 token 渲染為 plain span", () => {
    const nonInteractive: Token = {
      ...baseToken,
      id: "token-2",
      surface: "は",
      is_interactive: false,
      word_entry_id: null,
    };

    render(<TokenSpan token={nonInteractive} />);

    const element = screen.getByText("は");
    expect(element.tagName).toBe("SPAN");
    // 不應該有 button
    expect(screen.queryByRole("button")).toBeNull();
  });

  it("非互動式 token 不會觸發 onClick", () => {
    const handleClick = vi.fn();
    const nonInteractive: Token = {
      ...baseToken,
      id: "token-3",
      surface: "の",
      is_interactive: false,
      word_entry_id: null,
    };

    render(<TokenSpan token={nonInteractive} onClick={handleClick} />);

    fireEvent.click(screen.getByText("の"));
    expect(handleClick).not.toHaveBeenCalled();
  });

  // US2: Vocabulary status tests (T041, T042)
  it("vocabStatus=new の場合、vocab-underline クラスを持つ", () => {
    render(<TokenSpan token={baseToken} vocabStatus="new" />);

    const button = screen.getByRole("button");
    expect(button.className).toContain("vocab-underline");
    expect(button.getAttribute("data-vocab-status")).toBe("new");
  });

  it("vocabStatus=learning の場合、vocab-underline クラスを持つ", () => {
    render(<TokenSpan token={baseToken} vocabStatus="learning" />);

    const button = screen.getByRole("button");
    expect(button.className).toContain("vocab-underline");
    expect(button.getAttribute("data-vocab-status")).toBe("learning");
  });

  it("vocabStatus=known の場合、vocab-underline クラスを持たない", () => {
    render(<TokenSpan token={baseToken} vocabStatus="known" />);

    const button = screen.getByRole("button");
    expect(button.className).not.toContain("vocab-underline");
    expect(button.getAttribute("data-vocab-status")).toBe("known");
  });

  it("vocabStatus=unknown の場合（デフォルト）、vocab-underline を持たない", () => {
    render(<TokenSpan token={baseToken} />);

    const button = screen.getByRole("button");
    expect(button.className).not.toContain("vocab-underline");
    expect(button.getAttribute("data-vocab-status")).toBe("unknown");
  });

  // US4: Graduated underline intensity tests (T054)
  it("exposureCount=1 の場合、vocab-underline-light クラスを持つ", () => {
    render(<TokenSpan token={baseToken} vocabStatus="new" exposureCount={1} />);

    const button = screen.getByRole("button");
    expect(button.className).toContain("vocab-underline-light");
    expect(button.className).not.toContain("vocab-underline-dark");
  });

  it("exposureCount=2 の場合、vocab-underline-light クラスを持つ", () => {
    render(
      <TokenSpan token={baseToken} vocabStatus="learning" exposureCount={2} />,
    );

    const button = screen.getByRole("button");
    expect(button.className).toContain("vocab-underline-light");
  });

  it("exposureCount=3 の場合、vocab-underline-dark クラスを持つ", () => {
    render(
      <TokenSpan token={baseToken} vocabStatus="learning" exposureCount={3} />,
    );

    const button = screen.getByRole("button");
    expect(button.className).toContain("vocab-underline-dark");
    expect(button.className).not.toContain("vocab-underline-light");
  });

  it("exposureCount=4 の場合、vocab-underline-dark クラスを持つ", () => {
    render(
      <TokenSpan token={baseToken} vocabStatus="learning" exposureCount={4} />,
    );

    const button = screen.getByRole("button");
    expect(button.className).toContain("vocab-underline-dark");
  });

  it("exposureCount=5 の場合、underline クラスを持たない（卒業）", () => {
    render(
      <TokenSpan token={baseToken} vocabStatus="learning" exposureCount={5} />,
    );

    const button = screen.getByRole("button");
    expect(button.className).not.toContain("vocab-underline");
  });

  it("exposureCount=10 の場合、underline クラスを持たない", () => {
    render(
      <TokenSpan token={baseToken} vocabStatus="known" exposureCount={10} />,
    );

    const button = screen.getByRole("button");
    expect(button.className).not.toContain("vocab-underline");
  });

  it("vocabStatus=unknown の場合、exposureCount に関係なく underline を持たない", () => {
    render(
      <TokenSpan token={baseToken} vocabStatus="unknown" exposureCount={3} />,
    );

    const button = screen.getByRole("button");
    expect(button.className).not.toContain("vocab-underline");
  });

  it("onMouseEnter と onMouseLeave が正しく呼ばれる", () => {
    const handleMouseEnter = vi.fn();
    const handleMouseLeave = vi.fn();

    render(
      <TokenSpan
        token={baseToken}
        onMouseEnter={handleMouseEnter}
        onMouseLeave={handleMouseLeave}
      />,
    );

    const button = screen.getByRole("button");
    fireEvent.mouseEnter(button);
    expect(handleMouseEnter).toHaveBeenCalledWith(baseToken);

    fireEvent.mouseLeave(button);
    expect(handleMouseLeave).toHaveBeenCalledOnce();
  });
});
