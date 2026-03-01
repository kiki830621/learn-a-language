"use client";

import { useState, useEffect, useCallback, useMemo } from "react";
import { createBrowserSupabase } from "@/lib/supabase-browser";
import type { UserVocabRecord, VocabStatus } from "@/lib/types";

type UseUserVocabularyReturn = {
  isLoading: boolean;
  vocabMap: Map<string, UserVocabRecord>;
  getStatus: (wordEntryId: string) => VocabStatus;
  getExposureCount: (wordEntryId: string) => number;
  markAsKnown: (wordEntryId: string) => void;
  resetToLearning: (wordEntryId: string) => void;
};

/**
 * 使用者の語彙狀態を管理するフック
 *
 * Q4: 全ての user_vocabulary を取得し、word_entry_id → record のマップを提供。
 * M2/M3: markAsKnown / resetToLearning は楽観的に更新した後、Supabase に反映。
 */
export function useUserVocabulary(): UseUserVocabularyReturn {
  const [records, setRecords] = useState<UserVocabRecord[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  // Q4: Fetch all user vocabulary on mount
  useEffect(() => {
    let cancelled = false;
    const supabase = createBrowserSupabase();

    supabase
      .from("user_vocabulary")
      .select("word_entry_id, exposure_count, status")
      .then(({ data, error }) => {
        if (cancelled) return;
        if (!error && data) {
          setRecords(data as UserVocabRecord[]);
        }
        setIsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, []);

  // Build lookup map
  const vocabMap = useMemo(() => {
    const map = new Map<string, UserVocabRecord>();
    for (const record of records) {
      map.set(record.word_entry_id, record);
    }
    return map;
  }, [records]);

  // Get vocabulary status for a word entry
  const getStatus = useCallback(
    (wordEntryId: string): VocabStatus => {
      const record = vocabMap.get(wordEntryId);
      return record ? record.status : "unknown";
    },
    [vocabMap],
  );

  // Get exposure count for a word entry (US4: graduated underline)
  const getExposureCount = useCallback(
    (wordEntryId: string): number => {
      const record = vocabMap.get(wordEntryId);
      return record ? record.exposure_count : 0;
    },
    [vocabMap],
  );

  // M2: Mark as known (optimistic update)
  const markAsKnown = useCallback((wordEntryId: string) => {
    // Optimistic update
    setRecords((prev) =>
      prev.map((r) =>
        r.word_entry_id === wordEntryId
          ? { ...r, status: "known" as const }
          : r,
      ),
    );

    // Fire-and-forget Supabase update
    const supabase = createBrowserSupabase();
    supabase
      .from("user_vocabulary")
      .update({ status: "known", last_seen_at: new Date().toISOString() })
      .eq("word_entry_id", wordEntryId)
      .select()
      .then(() => {
        // Intentionally fire-and-forget
      });
  }, []);

  // M3: Reset to learning (optimistic update)
  const resetToLearning = useCallback((wordEntryId: string) => {
    // Optimistic update
    setRecords((prev) =>
      prev.map((r) =>
        r.word_entry_id === wordEntryId
          ? { ...r, status: "learning" as const, exposure_count: 0 }
          : r,
      ),
    );

    // Fire-and-forget Supabase update
    const supabase = createBrowserSupabase();
    supabase
      .from("user_vocabulary")
      .update({
        status: "learning",
        exposure_count: 0,
        last_seen_at: new Date().toISOString(),
      })
      .eq("word_entry_id", wordEntryId)
      .select()
      .then(() => {
        // Intentionally fire-and-forget
      });
  }, []);

  return {
    isLoading,
    vocabMap,
    getStatus,
    getExposureCount,
    markAsKnown,
    resetToLearning,
  };
}
