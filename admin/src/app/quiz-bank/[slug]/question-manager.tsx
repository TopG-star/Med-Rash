"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";

import { PILOT_QUESTION_OPTION_COUNT, type QuestionRecord } from "@/lib/quiz-bank-types";

import {
  createQuestionAction,
  deactivateQuestionAction,
  updateQuestionAction,
} from "../actions";

const OPTION_COUNT = PILOT_QUESTION_OPTION_COUNT; // 4 for pilot

const SUGGESTED_TAGS = ["guideline", "product"] as const;

type Props = {
  quizId: string;
  quizSlug: string;
  questions: QuestionRecord[];
};

type Draft = {
  prompt: string;
  options: string[];
  correctIndex: number;
  explanation: string;
  clinicalArea: string;
  tagsInput: string;
  isActive: boolean;
};

function blankDraft(): Draft {
  return {
    prompt: "",
    options: Array.from({ length: OPTION_COUNT }, () => ""),
    correctIndex: 0,
    explanation: "",
    clinicalArea: "",
    tagsInput: "",
    isActive: true,
  };
}

function fromQuestion(q: QuestionRecord): Draft {
  const padded = [...q.options];
  while (padded.length < OPTION_COUNT) padded.push("");
  return {
    prompt: q.prompt,
    options: padded.slice(0, OPTION_COUNT),
    correctIndex: Math.min(q.correctIndex, OPTION_COUNT - 1),
    explanation: q.explanation,
    clinicalArea: q.clinicalArea ?? "",
    tagsInput: q.tags.join(", "),
    isActive: q.isActive,
  };
}

export function QuestionManager({ quizId, quizSlug, questions }: Props) {
  const router = useRouter();
  const [editingId, setEditingId] = useState<string | "new" | null>(null);
  const [draft, setDraft] = useState<Draft>(blankDraft);
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  function startNew() {
    setEditingId("new");
    setDraft(blankDraft());
    setError(null);
  }

  function startEdit(q: QuestionRecord) {
    setEditingId(q.id);
    setDraft(fromQuestion(q));
    setError(null);
  }

  function cancel() {
    setEditingId(null);
    setDraft(blankDraft());
    setError(null);
  }

  function applyTagChip(tag: string) {
    const current = draft.tagsInput
      .split(",")
      .map((t) => t.trim().toLowerCase())
      .filter(Boolean);
    if (current.includes(tag)) return;
    current.push(tag);
    setDraft({ ...draft, tagsInput: current.join(", ") });
  }

  function submit() {
    setError(null);
    const tags = draft.tagsInput
      .split(",")
      .map((t) => t.trim())
      .filter((t) => t.length > 0);

    if (editingId === "new") {
      const payload = {
        quizId,
        prompt: draft.prompt,
        options: draft.options,
        correctIndex: draft.correctIndex,
        explanation: draft.explanation,
        clinicalArea: draft.clinicalArea || null,
        tags,
        isActive: draft.isActive,
      };
      startTransition(async () => {
        const result = await createQuestionAction(payload, quizSlug);
        if (!result.ok) {
          setError(result.message);
          return;
        }
        cancel();
        router.refresh();
      });
    } else if (editingId) {
      const payload = {
        id: editingId,
        prompt: draft.prompt,
        options: draft.options,
        correctIndex: draft.correctIndex,
        explanation: draft.explanation,
        clinicalArea: draft.clinicalArea || null,
        tags,
        isActive: draft.isActive,
      };
      startTransition(async () => {
        const result = await updateQuestionAction(payload, quizSlug);
        if (!result.ok) {
          setError(result.message);
          return;
        }
        cancel();
        router.refresh();
      });
    }
  }

  function deactivate(q: QuestionRecord) {
    setError(null);
    const ok = window.confirm(
      `Deactivate question "${q.prompt.slice(0, 80)}${q.prompt.length > 80 ? "…" : ""}"? Historical answers are preserved.`,
    );
    if (!ok) return;
    startTransition(async () => {
      const result = await deactivateQuestionAction(q.id, quizSlug);
      if (!result.ok) {
        setError(result.message);
        return;
      }
      router.refresh();
    });
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <p className="text-sm font-semibold text-[var(--arena-ink-muted)]">
          {questions.length} question{questions.length === 1 ? "" : "s"} · pilot fixed at{" "}
          {OPTION_COUNT} options each
        </p>
        {editingId === null ? (
          <button
            type="button"
            onClick={startNew}
            className="arena-button bg-[var(--arena-primary)] px-4 py-2 text-sm font-semibold"
          >
            Add Question
          </button>
        ) : null}
      </div>

      {editingId !== null ? (
        <DraftEditor
          draft={draft}
          setDraft={setDraft}
          onSubmit={submit}
          onCancel={cancel}
          onTagChip={applyTagChip}
          isPending={isPending}
          isNew={editingId === "new"}
          error={error}
        />
      ) : null}

      <ol className="space-y-3">
        {questions.map((q, idx) => (
          <li
            key={q.id}
            className="rounded-[16px] border-[3px] border-[var(--arena-outline)] bg-[var(--arena-surface)] px-4 py-4"
          >
            <div className="flex items-start justify-between gap-4">
              <div className="space-y-1">
                <p className="text-xs font-extrabold uppercase tracking-[0.05em] text-[var(--arena-ink-muted)]">
                  Q{idx + 1} · pos {q.position} · {q.isActive ? "active" : "inactive"}
                </p>
                <p className="font-semibold">{q.prompt}</p>
                <p className="text-xs text-[var(--arena-ink-muted)]">
                  Correct: {q.options[q.correctIndex] ?? "—"}
                </p>
                {q.tags.length > 0 ? (
                  <div className="flex flex-wrap gap-1 pt-1">
                    {q.tags.map((t) => (
                      <span
                        key={t}
                        className="rounded-full border-[2px] border-[var(--arena-outline)] bg-[var(--arena-secondary)] px-2 py-0.5 text-[10px] font-extrabold uppercase tracking-[0.05em]"
                      >
                        {t}
                      </span>
                    ))}
                  </div>
                ) : null}
              </div>
              {editingId === null ? (
                <div className="flex flex-col gap-2">
                  <button
                    type="button"
                    onClick={() => startEdit(q)}
                    className="arena-button bg-[var(--arena-surface)] px-3 py-1.5 text-xs font-semibold"
                  >
                    Edit
                  </button>
                  {q.isActive ? (
                    <button
                      type="button"
                      onClick={() => deactivate(q)}
                      className="arena-button bg-[var(--arena-danger)] px-3 py-1.5 text-xs font-semibold"
                    >
                      Deactivate
                    </button>
                  ) : null}
                </div>
              ) : null}
            </div>
          </li>
        ))}
      </ol>
    </div>
  );
}

type EditorProps = {
  draft: Draft;
  setDraft: (d: Draft) => void;
  onSubmit: () => void;
  onCancel: () => void;
  onTagChip: (tag: string) => void;
  isPending: boolean;
  isNew: boolean;
  error: string | null;
};

function DraftEditor({
  draft,
  setDraft,
  onSubmit,
  onCancel,
  onTagChip,
  isPending,
  isNew,
  error,
}: EditorProps) {
  return (
    <div className="space-y-4 rounded-[16px] border-[3px] border-[var(--arena-outline)] bg-[var(--arena-surface)] p-4">
      <h3 className="font-[family-name:var(--font-anybody)] text-lg font-extrabold uppercase tracking-tight">
        {isNew ? "New Question" : "Edit Question"}
      </h3>

      <label className="block space-y-2">
        <span className="text-sm font-semibold">Prompt</span>
        <textarea
          required
          rows={3}
          maxLength={1200}
          value={draft.prompt}
          onChange={(e) => setDraft({ ...draft, prompt: e.target.value })}
          className="arena-panel w-full px-4 py-3"
        />
      </label>

      <div className="space-y-2">
        <span className="text-sm font-semibold">
          Options (exactly {OPTION_COUNT}) — select the correct one
        </span>
        <div className="space-y-2">
          {draft.options.map((opt, idx) => (
            <div key={idx} className="flex items-center gap-3">
              <input
                type="radio"
                name="correctIndex"
                checked={draft.correctIndex === idx}
                onChange={() => setDraft({ ...draft, correctIndex: idx })}
              />
              <input
                required
                value={opt}
                maxLength={400}
                placeholder={`Option ${idx + 1}`}
                onChange={(e) => {
                  const next = [...draft.options];
                  next[idx] = e.target.value;
                  setDraft({ ...draft, options: next });
                }}
                className="arena-panel w-full px-3 py-2"
              />
            </div>
          ))}
        </div>
      </div>

      <label className="block space-y-2">
        <span className="text-sm font-semibold">
          Explanation (shown after the game, or intelligently after repeated misses)
        </span>
        <textarea
          required
          rows={3}
          maxLength={1200}
          value={draft.explanation}
          onChange={(e) => setDraft({ ...draft, explanation: e.target.value })}
          className="arena-panel w-full px-4 py-3"
        />
      </label>

      <div className="grid gap-4 md:grid-cols-2">
        <label className="space-y-2">
          <span className="text-sm font-semibold">Clinical area (optional)</span>
          <input
            value={draft.clinicalArea}
            maxLength={120}
            onChange={(e) => setDraft({ ...draft, clinicalArea: e.target.value })}
            className="arena-panel w-full px-4 py-3"
            placeholder="Cardiology"
          />
        </label>
        <label className="space-y-2">
          <span className="text-sm font-semibold">Tags (comma-separated)</span>
          <input
            value={draft.tagsInput}
            onChange={(e) => setDraft({ ...draft, tagsInput: e.target.value })}
            className="arena-panel w-full px-4 py-3"
            placeholder="guideline, product"
          />
          <div className="flex flex-wrap gap-2 pt-1">
            {SUGGESTED_TAGS.map((tag) => (
              <button
                key={tag}
                type="button"
                onClick={() => onTagChip(tag)}
                className="rounded-full border-[2px] border-[var(--arena-outline)] bg-[var(--arena-surface)] px-3 py-1 text-[11px] font-extrabold uppercase tracking-[0.05em]"
              >
                + {tag}
              </button>
            ))}
          </div>
        </label>
      </div>

      <label className="inline-flex items-center gap-2 text-sm font-semibold">
        <input
          type="checkbox"
          checked={draft.isActive}
          onChange={(e) => setDraft({ ...draft, isActive: e.target.checked })}
        />{" "}
        Active
      </label>

      {error ? (
        <p className="rounded-[12px] border-[2px] border-[var(--arena-danger)] bg-[var(--arena-surface)] px-4 py-3 text-sm font-semibold">
          {error}
        </p>
      ) : null}

      <div className="flex flex-wrap gap-3">
        <button
          type="button"
          disabled={isPending}
          onClick={onSubmit}
          className="arena-button bg-[var(--arena-primary)] px-6 py-3 font-semibold disabled:opacity-60"
        >
          {isPending ? "Saving…" : isNew ? "Create Question" : "Save Changes"}
        </button>
        <button
          type="button"
          disabled={isPending}
          onClick={onCancel}
          className="arena-button bg-[var(--arena-surface)] px-6 py-3 font-semibold disabled:opacity-60"
        >
          Cancel
        </button>
      </div>
    </div>
  );
}
