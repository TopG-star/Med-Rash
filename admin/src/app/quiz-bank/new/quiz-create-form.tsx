"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";

import { createQuizAction } from "../actions";

function slugify(input: string): string {
  return input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 64);
}

export function QuizCreateForm() {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [slug, setSlug] = useState("");
  const [slugTouched, setSlugTouched] = useState(false);

  function handleTitleChange(e: React.ChangeEvent<HTMLInputElement>) {
    if (!slugTouched) setSlug(slugify(e.target.value));
  }

  function handleSubmit(formData: FormData) {
    setError(null);
    const payload = {
      slug: String(formData.get("slug") ?? "").trim(),
      title: String(formData.get("title") ?? "").trim(),
      category: String(formData.get("category") ?? "").trim(),
      product: String(formData.get("product") ?? "").trim() || null,
      summary: String(formData.get("summary") ?? "").trim(),
      questionCountDefault: Number(formData.get("questionCountDefault") ?? 10),
      isActive: formData.get("isActive") === "on",
    };

    startTransition(async () => {
      const result = await createQuizAction(payload);
      if (!result.ok) {
        setError(result.message);
        return;
      }
      router.push(`/quiz-bank/${result.data.slug}`);
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
            onChange={handleTitleChange}
            className="arena-panel w-full px-4 py-3"
            placeholder="Clexane Indications Refresher"
          />
        </label>
        <label className="space-y-2">
          <span className="text-sm font-semibold">Slug</span>
          <input
            name="slug"
            required
            maxLength={64}
            value={slug}
            onChange={(e) => {
              setSlug(slugify(e.target.value));
              setSlugTouched(true);
            }}
            className="arena-panel w-full px-4 py-3"
            placeholder="clexane-indications"
            pattern="[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?"
            title="lowercase alphanumeric with optional dashes"
          />
        </label>
        <label className="space-y-2">
          <span className="text-sm font-semibold">Category</span>
          <input
            name="category"
            required
            maxLength={80}
            className="arena-panel w-full px-4 py-3"
            placeholder="Anticoagulation"
          />
        </label>
        <label className="space-y-2">
          <span className="text-sm font-semibold">Product (optional)</span>
          <input
            name="product"
            maxLength={80}
            className="arena-panel w-full px-4 py-3"
            placeholder="Clexane"
          />
        </label>
        <label className="space-y-2">
          <span className="text-sm font-semibold">Default Question Count</span>
          <input
            name="questionCountDefault"
            type="number"
            min={1}
            max={50}
            defaultValue={10}
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
            className="arena-panel w-full px-4 py-3"
            placeholder="Short description shown to participants."
          />
        </label>
        <label className="md:col-span-2 inline-flex items-center gap-2 text-sm font-semibold">
          <input type="checkbox" name="isActive" defaultChecked /> Active
        </label>
      </div>

      {error ? (
        <p className="rounded-[12px] border-[2px] border-[var(--arena-danger)] bg-[var(--arena-surface)] px-4 py-3 text-sm font-semibold">
          {error}
        </p>
      ) : null}

      <button
        type="submit"
        disabled={isPending}
        className="arena-button bg-[var(--arena-primary)] px-6 py-3 font-semibold disabled:opacity-60"
      >
        {isPending ? "Creating…" : "Create Quiz"}
      </button>
    </form>
  );
}
