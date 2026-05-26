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
    <div className="vp-vstack vp-vstack-md">
      <div className="vp-row">
        <p className="vp-q-meta">
          {questions.length} question{questions.length === 1 ? "" : "s"} · pilot
          fixed at {OPTION_COUNT} options each
        </p>
        {editingId === null ? (
          <button
            type="button"
            onClick={startNew}
            className="vp-button vp-button-primary"
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

      <ol className="vp-q-list">
        {questions.map((q, idx) => (
          <li key={q.id} className="vp-q-row">
            <div className="vp-q-row-head">
              <div className="vp-min-w-0">
                <p className="vp-q-pos">
                  Q{idx + 1} · pos {q.position} ·{" "}
                  {q.isActive ? "active" : "inactive"}
                </p>
                <p className="vp-q-prompt">{q.prompt}</p>
                <p className="vp-q-meta">
                  Correct: {q.options[q.correctIndex] ?? "—"}
                </p>
                {q.tags.length > 0 ? (
                  <div className="vp-q-tags">
                    {q.tags.map((t) => (
                      <span key={t} className="vp-tag">
                        {t}
                      </span>
                    ))}
                  </div>
                ) : null}
              </div>
              {editingId === null ? (
                <div className="vp-q-actions">
                  <button
                    type="button"
                    onClick={() => startEdit(q)}
                    className="vp-button vp-button-secondary vp-btn-sm"
                  >
                    Edit
                  </button>
                  {q.isActive ? (
                    <button
                      type="button"
                      onClick={() => deactivate(q)}
                      className="vp-button vp-button-danger vp-btn-sm"
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
    <div className="vp-editor">
      <h3 className="vp-editor-title">
        {isNew ? "New Question" : "Edit Question"}
      </h3>

      <label className="vp-field">
        <span className="vp-label">Prompt</span>
        <textarea
          required
          rows={3}
          maxLength={1200}
          value={draft.prompt}
          onChange={(e) => setDraft({ ...draft, prompt: e.target.value })}
          className="vp-textarea"
        />
      </label>

      <div className="vp-field">
        <span className="vp-label">
          Options (exactly {OPTION_COUNT}) — select the correct one
        </span>
        <div className="vp-option-list">
          {draft.options.map((opt, idx) => (
            <div key={idx} className="vp-option-row">
              <input
                type="radio"
                name="correctIndex"
                aria-label={`Mark option ${idx + 1} correct`}
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
                className="vp-input"
              />
            </div>
          ))}
        </div>
      </div>

      <label className="vp-field">
        <span className="vp-label">
          Explanation (shown after the game, or intelligently after repeated misses)
        </span>
        <textarea
          required
          rows={3}
          maxLength={1200}
          value={draft.explanation}
          onChange={(e) => setDraft({ ...draft, explanation: e.target.value })}
          className="vp-textarea"
        />
      </label>

      <div className="vp-form-grid cols-2">
        <label className="vp-field">
          <span className="vp-label">Clinical area (optional)</span>
          <input
            value={draft.clinicalArea}
            maxLength={120}
            onChange={(e) => setDraft({ ...draft, clinicalArea: e.target.value })}
            className="vp-input"
            placeholder="Cardiology"
          />
        </label>
        <label className="vp-field">
          <span className="vp-label">Tags (comma-separated)</span>
          <input
            value={draft.tagsInput}
            onChange={(e) => setDraft({ ...draft, tagsInput: e.target.value })}
            className="vp-input"
            placeholder="guideline, product"
          />
          <div className="vp-row-chips">
            {SUGGESTED_TAGS.map((tag) => (
              <button
                key={tag}
                type="button"
                onClick={() => onTagChip(tag)}
                className="vp-tag-add"
              >
                + {tag}
              </button>
            ))}
          </div>
        </label>
      </div>

      <label className="vp-checkbox-row">
        <input
          type="checkbox"
          checked={draft.isActive}
          onChange={(e) => setDraft({ ...draft, isActive: e.target.checked })}
        />{" "}
        Active
      </label>

      {error ? <p className="vp-banner vp-banner-error">{error}</p> : null}

      <div className="vp-button-row">
        <button
          type="button"
          disabled={isPending}
          onClick={onSubmit}
          className="vp-button vp-button-primary"
        >
          {isPending ? "Saving…" : isNew ? "Create Question" : "Save Changes"}
        </button>
        <button
          type="button"
          disabled={isPending}
          onClick={onCancel}
          className="vp-button vp-button-secondary"
        >
          Cancel
        </button>
      </div>
    </div>
  );
}
