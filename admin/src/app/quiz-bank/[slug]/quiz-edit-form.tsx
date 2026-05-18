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
    <form action={handleSubmit} className="space-y-4">
      <div className="grid gap-4 md:grid-cols-2">
        <label className="md:col-span-2 space-y-2">
          <span className="text-sm font-semibold">Title</span>
          <input
            name="title"
            required
            maxLength={160}
            defaultValue={quiz.title}
            className="arena-panel w-full px-4 py-3"
          />
        </label>
        <label className="space-y-2">
          <span className="text-sm font-semibold">Category</span>
          <input
            name="category"
            required
            maxLength={80}
            defaultValue={quiz.category}
            className="arena-panel w-full px-4 py-3"
          />
        </label>
        <label className="space-y-2">
          <span className="text-sm font-semibold">Product (optional)</span>
          <input
            name="product"
            maxLength={80}
            defaultValue={quiz.product ?? ""}
            className="arena-panel w-full px-4 py-3"
          />
        </label>
        <label className="space-y-2">
          <span className="text-sm font-semibold">Default Question Count</span>
          <input
            name="questionCountDefault"
            type="number"
            min={1}
            max={50}
            defaultValue={quiz.questionCountDefault}
            required
            className="arena-panel w-full px-4 py-3"
          />
        </label>
        <label className="md:col-span-2 space-y-2">
          <span className="text-sm font-semibold">Summary</span>
          <textarea
            name="summary"
            required
            maxLength={600}
            rows={3}
            defaultValue={quiz.summary}
            className="arena-panel w-full px-4 py-3"
          />
        </label>
        <label className="md:col-span-2 inline-flex items-center gap-2 text-sm font-semibold">
          <input type="checkbox" name="isActive" defaultChecked={quiz.isActive} /> Active
        </label>
      </div>

      {error ? (
        <p className="rounded-[12px] border-[2px] border-[var(--arena-danger)] bg-[var(--arena-surface)] px-4 py-3 text-sm font-semibold">
          {error}
        </p>
      ) : null}
      {info ? (
        <p className="rounded-[12px] border-[2px] border-[var(--arena-outline)] bg-[var(--arena-surface)] px-4 py-3 text-sm font-semibold">
          {info}
        </p>
      ) : null}

      <div className="flex flex-wrap gap-3">
        <button
          type="submit"
          disabled={isSaving}
          className="arena-button bg-[var(--arena-primary)] px-6 py-3 font-semibold disabled:opacity-60"
        >
          {isSaving ? "Saving…" : "Save Changes"}
        </button>
        {quiz.isActive ? (
          <button
            type="button"
            onClick={handleDeactivate}
            disabled={isDeactivating}
            className="arena-button bg-[var(--arena-danger)] px-6 py-3 font-semibold disabled:opacity-60"
          >
            {isDeactivating ? "Deactivating…" : "Deactivate Quiz"}
          </button>
        ) : null}
      </div>
    </form>
  );
}
