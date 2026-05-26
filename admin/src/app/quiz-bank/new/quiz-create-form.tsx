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
    <form action={handleSubmit} className="vp-vstack vp-vstack-lg">
      <div className="vp-form-grid cols-2">
        <label className="vp-field col-span-2">
          <span className="vp-label">Title</span>
          <input
            name="title"
            required
            maxLength={160}
            onChange={handleTitleChange}
            className="vp-input"
            placeholder="Clexane Indications Refresher"
          />
        </label>
        <label className="vp-field">
          <span className="vp-label">Slug</span>
          <input
            name="slug"
            required
            maxLength={64}
            value={slug}
            onChange={(e) => {
              setSlug(slugify(e.target.value));
              setSlugTouched(true);
            }}
            className="vp-input"
            placeholder="clexane-indications"
            pattern="[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?"
            title="lowercase alphanumeric with optional dashes"
          />
        </label>
        <label className="vp-field">
          <span className="vp-label">Category</span>
          <input
            name="category"
            required
            maxLength={80}
            className="vp-input"
            placeholder="Anticoagulation"
          />
        </label>
        <label className="vp-field">
          <span className="vp-label">Product (optional)</span>
          <input
            name="product"
            maxLength={80}
            className="vp-input"
            placeholder="Clexane"
          />
        </label>
        <label className="vp-field">
          <span className="vp-label">Default Question Count</span>
          <input
            name="questionCountDefault"
            type="number"
            min={1}
            max={50}
            defaultValue={10}
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
            className="vp-textarea"
            placeholder="Short description shown to participants."
          />
        </label>
        <label className="vp-checkbox-row col-span-2">
          <input type="checkbox" name="isActive" defaultChecked /> Active
        </label>
      </div>

      {error ? <p className="vp-banner vp-banner-error">{error}</p> : null}

      <div className="vp-button-row">
        <button
          type="submit"
          disabled={isPending}
          className="vp-button vp-button-primary"
        >
          {isPending ? "Creating…" : "Create Quiz"}
        </button>
      </div>
    </form>
  );
}
