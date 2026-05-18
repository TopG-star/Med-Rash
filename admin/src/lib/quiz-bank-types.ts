/**
 * Client-safe shared types and constants for the Quiz Bank surface.
 *
 * Importing this file from a Client Component is intentionally allowed —
 * it must NOT depend on `server-only`, the Supabase client, or any other
 * server-only module.
 */

export const PILOT_QUESTION_OPTION_COUNT = 4;

export type QuizRecord = {
  id: string;
  slug: string;
  title: string;
  category: string;
  product: string | null;
  summary: string;
  questionCountDefault: number;
  isActive: boolean;
  metadata: Record<string, unknown>;
  createdAt: string;
  updatedAt: string;
};

export type QuestionRecord = {
  id: string;
  quizId: string;
  prompt: string;
  options: string[];
  correctIndex: number;
  explanation: string;
  clinicalArea: string | null;
  tags: string[];
  position: number;
  isActive: boolean;
  createdAt: string;
};
