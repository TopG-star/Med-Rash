import { describe, it, expect } from "vitest";
import { validateBody } from "./_helpers";
import { identityInputSchema, loginRequestOtpSchema, loginVerifyOtpSchema } from "./identity";
import { recoverRequestSchema, recoverVerifySchema } from "./recover";
import { attemptSubmitSchema } from "./attempt";
import {
  createSessionSchema,
  sessionResolveSchema,
  sessionLeaderboardSchema,
  sessionCloseSchema,
} from "./session";
import {
  inviteAdminSchema,
  setRoleSchema,
  userIdInputSchema,
} from "./admin-users";
import { completeOnboardingSchema } from "./onboarding";
import {
  quizBankWriteSchema,
  createQuizPayloadSchema,
  createQuestionPayloadSchema,
} from "./quiz";
import {
  leaderboardSchema,
  rankedEligibilitySchema,
  profileSyncSchema,
} from "./leaderboard";

describe("validateBody envelope", () => {
  it("returns ok=true with parsed data on success", () => {
    const result = validateBody(recoverRequestSchema, { email: " A@B.COM " });
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.data.email).toBe("a@b.com");
  });

  it("returns code=invalid_input with issues on failure", () => {
    const result = validateBody(recoverRequestSchema, { email: "nope" });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("invalid_input");
      expect(result.issues.length).toBeGreaterThan(0);
      expect(result.issues[0]?.path).toBe("email");
    }
  });
});

describe("identity schemas", () => {
  it("happy: identityInputSchema accepts trimmed id + device + profile", () => {
    const r = identityInputSchema.safeParse({
      participantId: " pid ",
      deviceInstallId: " dev ",
      profile: { nickname: " Doc " },
    });
    expect(r.success).toBe(true);
    if (r.success) {
      expect(r.data.participantId).toBe("pid");
      expect(r.data.deviceInstallId).toBe("dev");
      expect(r.data.profile?.nickname).toBe("Doc");
    }
  });

  it("rejects empty participantId", () => {
    const r = identityInputSchema.safeParse({ participantId: "  ", deviceInstallId: "dev" });
    expect(r.success).toBe(false);
  });

  it("rejects missing deviceInstallId", () => {
    const r = identityInputSchema.safeParse({ participantId: "pid" });
    expect(r.success).toBe(false);
  });

  it("rejects non-string participantId", () => {
    const r = identityInputSchema.safeParse({ participantId: 42, deviceInstallId: "dev" });
    expect(r.success).toBe(false);
  });

  it("loginRequestOtp happy lowercases email", () => {
    const r = loginRequestOtpSchema.safeParse({ email: " A@B.com" });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.email).toBe("a@b.com");
  });

  it("loginVerifyOtp strips spaces from token", () => {
    const r = loginVerifyOtpSchema.safeParse({ email: "a@b.com", token: "12 34 56" });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.token).toBe("123456");
  });

  it("loginVerifyOtp rejects non-6-digit token", () => {
    const r = loginVerifyOtpSchema.safeParse({ email: "a@b.com", token: "12345" });
    expect(r.success).toBe(false);
  });

  it("loginVerifyOtp rejects letter token", () => {
    const r = loginVerifyOtpSchema.safeParse({ email: "a@b.com", token: "abcdef" });
    expect(r.success).toBe(false);
  });
});

describe("recover schemas", () => {
  it("recoverRequest happy", () => {
    const r = recoverRequestSchema.safeParse({ email: "U@x.co" });
    expect(r.success).toBe(true);
  });
  it("recoverRequest rejects missing email", () => {
    expect(recoverRequestSchema.safeParse({}).success).toBe(false);
  });
  it("recoverRequest rejects malformed email", () => {
    expect(recoverRequestSchema.safeParse({ email: "no-at-sign" }).success).toBe(false);
  });
  it("recoverRequest rejects > 254 char email", () => {
    const local = "a".repeat(250);
    expect(recoverRequestSchema.safeParse({ email: `${local}@x.co` }).success).toBe(false);
  });

  it("recoverVerify happy", () => {
    const r = recoverVerifySchema.safeParse({
      email: "a@b.co",
      otp: " 123456 ",
      deviceInstallId: "dev",
    });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.otp).toBe("123456");
  });
  it("recoverVerify rejects bad otp", () => {
    const r = recoverVerifySchema.safeParse({ email: "a@b.co", otp: "12", deviceInstallId: "dev" });
    expect(r.success).toBe(false);
  });
  it("recoverVerify rejects missing deviceInstallId", () => {
    const r = recoverVerifySchema.safeParse({ email: "a@b.co", otp: "123456" });
    expect(r.success).toBe(false);
  });
});

describe("attempt schema", () => {
  const valid = {
    participantId: "pid",
    deviceInstallId: "dev",
    quizId: "quiz-1",
    mode: "ranked",
    origin: "open_access",
    sessionId: null,
    score: 5,
    totalQuestions: 5,
    timeTakenMs: 1000,
    answers: [{ questionId: "q1", selectedIndex: 0 }],
  };

  it("happy", () => {
    const r = attemptSubmitSchema.safeParse(valid);
    expect(r.success).toBe(true);
  });

  it("rejects qr_session without sessionId", () => {
    const r = attemptSubmitSchema.safeParse({ ...valid, origin: "qr_session", sessionId: null });
    expect(r.success).toBe(false);
  });

  it("clamps timeTakenMs > 2h", () => {
    const r = attemptSubmitSchema.safeParse({ ...valid, timeTakenMs: 99_999_999 });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.timeTakenMs).toBe(2 * 60 * 60 * 1000);
  });

  it("rejects missing answers", () => {
    const { answers, ...rest } = valid;
    void answers;
    const r = attemptSubmitSchema.safeParse(rest);
    expect(r.success).toBe(false);
  });
});

describe("session schemas", () => {
  it("createSession happy", () => {
    const r = createSessionSchema.safeParse({
      quizId: "q",
      name: "S1",
      hostName: "Host",
      startsAt: "2026-01-01T00:00:00Z",
      endsAt: "2026-01-02T00:00:00Z",
      mode: "ranked",
    });
    expect(r.success).toBe(true);
  });
  it("rejects endsAt < startsAt", () => {
    const r = createSessionSchema.safeParse({
      quizId: "q",
      name: "S1",
      startsAt: "2026-01-02T00:00:00Z",
      endsAt: "2026-01-01T00:00:00Z",
    });
    expect(r.success).toBe(false);
  });
  it("rejects empty name", () => {
    expect(createSessionSchema.safeParse({ quizId: "q", name: " " }).success).toBe(false);
  });
  it("rejects invalid startsAt", () => {
    expect(
      createSessionSchema.safeParse({ quizId: "q", name: "S1", startsAt: "not-a-date" }).success,
    ).toBe(false);
  });

  it("sessionResolve happy uppercases joinCode", () => {
    const r = sessionResolveSchema.safeParse({ joinCode: " abc123 " });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.joinCode).toBe("ABC123");
  });
  it("sessionResolve rejects missing joinCode", () => {
    expect(sessionResolveSchema.safeParse({}).success).toBe(false);
  });

  it("sessionLeaderboard happy applies default limit", () => {
    const r = sessionLeaderboardSchema.safeParse({
      sessionId: "abc-123",
      participantId: "p-1",
      deviceInstallId: "d-1",
    });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.limit).toBe(50);
  });
  it("sessionLeaderboard clamps limit into [1,100] range", () => {
    const r = sessionLeaderboardSchema.safeParse({
      sessionId: "abc-123",
      participantId: "p-1",
      deviceInstallId: "d-1",
      limit: 500,
    });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.limit).toBe(100);
  });
  it("sessionLeaderboard rejects missing sessionId", () => {
    const r = sessionLeaderboardSchema.safeParse({
      participantId: "p-1",
      deviceInstallId: "d-1",
    });
    expect(r.success).toBe(false);
  });
  it("sessionLeaderboard rejects missing identity fields", () => {
    expect(
      sessionLeaderboardSchema.safeParse({
        sessionId: "abc",
        participantId: "p-1",
      }).success,
    ).toBe(false);
    expect(
      sessionLeaderboardSchema.safeParse({
        sessionId: "abc",
        deviceInstallId: "d-1",
      }).success,
    ).toBe(false);
  });

  it("sessionClose happy", () => {
    const r = sessionCloseSchema.safeParse({ sessionId: " abc-123 " });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.sessionId).toBe("abc-123");
  });
  it("sessionClose rejects empty sessionId", () => {
    expect(sessionCloseSchema.safeParse({ sessionId: "" }).success).toBe(false);
    expect(sessionCloseSchema.safeParse({}).success).toBe(false);
  });
});

describe("quiz schemas", () => {
  it("createQuiz happy", () => {
    const r = createQuizPayloadSchema.safeParse({
      slug: "Cme-101",
      title: "T",
      category: "CME",
      summary: "S",
      questionCountDefault: 10,
    });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.slug).toBe("cme-101");
  });
  it("rejects bad slug", () => {
    const r = createQuizPayloadSchema.safeParse({
      slug: "Has Space",
      title: "T",
      category: "CME",
      summary: "S",
      questionCountDefault: 10,
    });
    expect(r.success).toBe(false);
  });
  it("rejects questionCountDefault out of range", () => {
    const r = createQuizPayloadSchema.safeParse({
      slug: "ok",
      title: "T",
      category: "CME",
      summary: "S",
      questionCountDefault: 100,
    });
    expect(r.success).toBe(false);
  });

  it("createQuestion rejects non-4 options", () => {
    const r = createQuestionPayloadSchema.safeParse({
      quizId: "q",
      prompt: "P",
      options: ["a", "b", "c"],
      correctIndex: 0,
      explanation: "E",
    });
    expect(r.success).toBe(false);
  });
  it("createQuestion rejects duplicate options", () => {
    const r = createQuestionPayloadSchema.safeParse({
      quizId: "q",
      prompt: "P",
      options: ["a", "A", "b", "c"],
      correctIndex: 0,
      explanation: "E",
    });
    expect(r.success).toBe(false);
  });

  it("quizBankWrite happy create_quiz", () => {
    const r = quizBankWriteSchema.safeParse({
      op: "create_quiz",
      payload: {
        slug: "ok",
        title: "T",
        category: "CME",
        summary: "S",
        questionCountDefault: 5,
      },
    });
    expect(r.success).toBe(true);
  });
  it("quizBankWrite rejects unknown op", () => {
    expect(quizBankWriteSchema.safeParse({ op: "explode" }).success).toBe(false);
  });
  it("quizBankWrite rejects deactivate without id", () => {
    expect(quizBankWriteSchema.safeParse({ op: "deactivate_quiz" }).success).toBe(false);
  });
});

describe("leaderboard schemas", () => {
  it("happy with defaults", () => {
    const r = leaderboardSchema.safeParse({});
    expect(r.success).toBe(true);
    if (r.success) {
      expect(r.data.type).toBe("allTime");
      expect(r.data.limit).toBe(50);
      expect(r.data.season).toBe(null);
    }
  });
  it("clamps limit > 100", () => {
    const r = leaderboardSchema.safeParse({ limit: 9999 });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.limit).toBe(100);
  });
  it("nulls invalid season", () => {
    const r = leaderboardSchema.safeParse({ type: "monthly", season: "garbage" });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.season).toBe(null);
  });
  it("accepts well-formed season", () => {
    const r = leaderboardSchema.safeParse({ type: "monthly", season: "2026-05" });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.season).toBe("2026-05");
  });

  it("rankedEligibility happy", () => {
    const r = rankedEligibilitySchema.safeParse({
      participantId: " pid ",
      deviceInstallId: " dev ",
      quizId: " q ",
    });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.quizId).toBe("q");
  });
  it("rankedEligibility rejects missing quizId", () => {
    expect(
      rankedEligibilitySchema.safeParse({ participantId: "p", deviceInstallId: "d" }).success,
    ).toBe(false);
  });

  it("profileSync happy", () => {
    expect(
      profileSyncSchema.safeParse({ participantId: "p", deviceInstallId: "d" }).success,
    ).toBe(true);
  });
  it("profileSync rejects empty participantId", () => {
    expect(profileSyncSchema.safeParse({ participantId: "", deviceInstallId: "d" }).success).toBe(
      false,
    );
  });
});


describe("admin-users schemas", () => {
  it("inviteAdmin happy lowercases email + defaults role to host", () => {
    const r = inviteAdminSchema.safeParse({ email: " A@B.co" });
    expect(r.success).toBe(true);
    if (r.success) {
      expect(r.data.email).toBe("a@b.co");
      expect(r.data.role).toBe("host");
    }
  });
  it("inviteAdmin accepts role=owner", () => {
    const r = inviteAdminSchema.safeParse({ email: "a@b.co", role: "owner" });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.role).toBe("owner");
  });
  it("inviteAdmin rejects bad email", () => {
    expect(inviteAdminSchema.safeParse({ email: "nope" }).success).toBe(false);
  });
  it("inviteAdmin rejects unknown role", () => {
    expect(inviteAdminSchema.safeParse({ email: "a@b.co", role: "guest" }).success).toBe(false);
  });
  it("userIdInput happy trims", () => {
    const r = userIdInputSchema.safeParse({ userId: " uid " });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.userId).toBe("uid");
  });
  it("userIdInput rejects empty", () => {
    expect(userIdInputSchema.safeParse({ userId: "  " }).success).toBe(false);
  });
  it("setRole happy", () => {
    const r = setRoleSchema.safeParse({ userId: "uid", role: "owner" });
    expect(r.success).toBe(true);
  });
  it("setRole rejects bad role", () => {
    expect(setRoleSchema.safeParse({ userId: "uid", role: "guest" }).success).toBe(false);
  });
});

describe("onboarding schemas", () => {
  it("completeOnboarding happy trims", () => {
    const r = completeOnboardingSchema.safeParse({
      fullName: " Dr Foo ",
      company: " Pharma Co ",
      jobRole: "MSR",
    });
    expect(r.success).toBe(true);
    if (r.success) {
      expect(r.data.fullName).toBe("Dr Foo");
      expect(r.data.company).toBe("Pharma Co");
      expect(r.data.jobRole).toBe("MSR");
    }
  });
  it("rejects fullName < 2", () => {
    expect(
      completeOnboardingSchema.safeParse({ fullName: "A", company: "Foo", jobRole: "MSR" }).success,
    ).toBe(false);
  });
  it("rejects fullName > 120", () => {
    expect(
      completeOnboardingSchema.safeParse({
        fullName: "a".repeat(121),
        company: "Foo",
        jobRole: "MSR",
      }).success,
    ).toBe(false);
  });
  it("rejects company < 2", () => {
    expect(
      completeOnboardingSchema.safeParse({ fullName: "Foo", company: "x", jobRole: "MSR" }).success,
    ).toBe(false);
  });
  it("rejects unknown jobRole", () => {
    expect(
      completeOnboardingSchema.safeParse({ fullName: "Foo", company: "Bar", jobRole: "CEO" })
        .success,
    ).toBe(false);
  });
  it("accepts Manager role", () => {
    const r = completeOnboardingSchema.safeParse({
      fullName: "Foo",
      company: "Bar",
      jobRole: "Manager",
    });
    expect(r.success).toBe(true);
  });
});
