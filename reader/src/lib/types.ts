// Work list (Q1)
export type WorkListItem = {
  id: string;
  title: string;
  author: string;
  publish_year: number | null;
  token_count: number;
  processed_at: string;
};

// Token in a work (Q2) — BCNF: base_form, pos, reading, sentence_text
// removed (available via word_entry_id JOIN / sentence_id JOIN)
export type Token = {
  id: string;
  position: number;
  surface: string;
  is_interactive: boolean;
  word_entry_id: string | null;
  sentence_id: string | null;
};

// Word entry for tooltip (Q3) — BCNF: cross_text_examples and work_count removed
export type WordEntry = {
  id: string;
  base_form: string;
  pos: string;
  reading: string;
  jmdict_def: string | null;
  ai_explanation: string | null;
};

// Cross-text example (display type — joined from cross_text_examples + sentences + works)
export type CrossTextExample = {
  work_id: string;
  work_title: string;
  author: string;
  sentence: string;
  token_position: number;
};

// User vocabulary record (Q4)
export type UserVocabRecord = {
  word_entry_id: string;
  exposure_count: number;
  status: "new" | "learning" | "known";
};

// Vocabulary status for UI
export type VocabStatus = "unknown" | "new" | "learning" | "known";

// POS categories for tooltip content strategy
export const NOUN_POS = ["名詞"] as const;
export const VERB_POS = ["動詞"] as const;
export const ADJ_POS = ["形容詞", "形状詞"] as const;

export function getTooltipStrategy(pos: string): "definition" | "examples" {
  if (VERB_POS.includes(pos as any) || ADJ_POS.includes(pos as any)) {
    return "examples";
  }
  return "definition";
}
