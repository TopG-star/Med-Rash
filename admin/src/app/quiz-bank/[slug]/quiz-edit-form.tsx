"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";

import type { QuizRecord } from "@/lib/quiz-bank-types";

import { deactivateQuizAction, updateQuizAction } from "../actions";

type Props = { quiz: QuizRecord };

export function QuizEditForm({ quiz }: Props) {
  const router = useRouter();
  const [isSaving, startSave] = useTransition();
  const [isDeactivating, startDeactivate] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);

  function handleSubmit(formData: FormData) {
    setError(null);
    setInfo(null);
    const payload = {
      id: quiz.id,
      title: String(formData.get("title") ?? "").trim(),
      category: String(formData.get("category") ?? "").trim(),
      product: String(formData.get("product") ?? "").trim() || null,
      summary: String(formData.get("summary") ?? "").trim(),
      questionCountDefault: Number(formData.get("questionCountDefault") ?? 10),
      isActive: formData.get("isActive") === "on",
    };

    startSave(async () => {
      const result = await updateQuizAction(payload);
      if (!result.ok) {
        setError(result.message);
        return;
      }
      setInfo("Quiz updated.");
      router.refresh();
    });
  }

  function handleDeactivate() {
    setError(null);
    setInfo(null);
    const ok = window.confirm(
      `Deactivate "${quiz.title}"? Participants will no longer see it. Historical attempts are preserved.`,
    );
    if (!ok) return;
    startDeactivate(async () => {
      const result = await deactivateQuizAction(quiz.id, quiz.slug);
      if (!result.ok) {
        setError(result.message);
        return;
      }
      setInfo("Quiz deactivated.");
      router.refresh();
    });
  }

  return (
    <form action={handleSubmit} className="vp-vstack vp-vstack-lg">
      <div className="vp-form-grid cols-2">
        <label className="vp-field col-span-2">
          <span className="vp-label">Title</span>
          <input
            name="title"
            required
            maxLength={160}
            defaultValue={quiz.title}
            className="vp-input"
          />
        </label>
        <label className="vp-field">
          <span className="vp-label">Category</span>
          <input
            name="category"
            required
            maxLength={80}
            defaultValue={quiz.category}
            className="vp-input"
          />
        </label>
        <label className="vp-field">
          <span className="vp-label">Product (optional)</span>
          <input
            name="product"
            maxLength={80}
            defaultValue={quiz.product ?? ""}
            className="vp-input"
          />
        </label>
        <label className="vp-field">
          <span className="vp-label">Default Question Count</span>
          <input
            name="questionCountDefault"
            type="number"
            min={1}
            max={50}
            defaultValue={quiz.questionCountDefault}
            required
            className="vp-input"
          />
        </label>
        <label className="vp-field col-span-2">
          <span className="vp-label">Summary</span>
          <textarea
            name="summary"
            required
            maxLength={600}
            rows={3}
            defaultValue={quiz.summary}
            className="vp-textarea"
          />
        </label>
        <label className="vp-checkbox-row col-span-2">
          <input type="checkbox" name="isActive" defaultChecked={quiz.isActive} /> Active
        </label>
      </div>

      {error ? <p className="vp-banner vp-banner-error">{error}</p> : null}
      {info ? <p className="vp-banner vp-banner-success">{info}</p> : null}

      <div className="vp-button-row">
        <button
          type="submit"
          disabled={isSaving}
          className="vp-button vp-button-primary"
        >
          {isSaving ? "Saving…" : "Save Changes"}
        </button>
        {quiz.isActive ? (
          <button
            type="button"
            onClick={handleDeactivate}
            disabled={isDeactivating}
            className="vp-button vp-button-danger"
          >
            {isDeactivating ? "Deactivating…" : "Deactivate Quiz"}
          </button>
        ) : null}
      </div>
    </form>
  );
}
