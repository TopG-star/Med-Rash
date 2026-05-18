insert into app.users (id, full_name, nickname, facility, specialty, profession)
values
  ('11111111-1111-1111-1111-111111111111', 'Joshua Mensah', 'SwiftDoctor777', 'Korle-Bu Teaching Hospital', 'Emergency Medicine', 'Doctor'),
  ('22222222-2222-2222-2222-222222222222', 'Setor Asante', 'Setor', 'Komfo Anokye Teaching Hospital', 'Cardiology', 'Doctor'),
  ('33333333-3333-3333-3333-333333333333', 'Papa Ekow Boadi', 'PapaEkow', 'Cape Coast Teaching Hospital', 'Pharmacy', 'Pharmacist'),
  ('44444444-4444-4444-4444-444444444444', 'Edward Kyei', 'eddykay7', 'Tamale Teaching Hospital', 'Internal Medicine', 'Doctor')
on conflict (id) do nothing;

insert into app.user_devices (user_id, device_install_id)
values
  ('11111111-1111-1111-1111-111111111111', 'medrash-demo-device-1'),
  ('22222222-2222-2222-2222-222222222222', 'medrash-demo-device-2'),
  ('33333333-3333-3333-3333-333333333333', 'medrash-demo-device-3'),
  ('44444444-4444-4444-4444-444444444444', 'medrash-demo-device-4')
on conflict (device_install_id) do nothing;

insert into app.quizzes (id, slug, title, category, summary, question_count_default)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'clexane-vte-masterclass', 'Clexane VTE Master Class', 'VTE', 'Live and post-session learning checks on DVT and PE risk recognition and management.', 5),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'tavanic-infection-stewardship', 'Tavanic Infection Stewardship', 'UTI/Infections', 'Field-focused stewardship and treatment awareness checks for infection practice contexts.', 5),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'aprovel-hypertension-practice', 'Aprovel Hypertension Practice', 'Hypertension', 'Applied hypertension treatment-awareness checks for mixed HCP audiences.', 5),
  ('aaaaaaaa-0000-0000-0000-000000000004', 'lantus-basal-diabetes-care', 'Lantus Basal Diabetes Care', 'Diabetes', 'Basal insulin practical knowledge checks for initiation and follow-up.', 5),
  ('aaaaaaaa-0000-0000-0000-000000000005', 'utrogestan-fertility-and-hormonal-care', 'Utrogestan Fertility And Hormonal Care', 'Fertility/Hormonal Imbalances', 'Master class reinforcement on progesterone-support clinical pathways.', 5),
  ('aaaaaaaa-0000-0000-0000-000000000006', 'androgel-testosterone-deficiency-care', 'Androgel Testosterone Deficiency Care', 'Testosterone Deficiency', 'Awareness and practice checks for testosterone-deficiency management contexts.', 5)
on conflict (id) do nothing;

insert into app.questions (id, quiz_id, prompt, options, correct_index, explanation, clinical_area, tags)
values
  (
    'bbbbbbbb-0000-0000-0000-000000000001',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'In a VTE-focused master class, which signal should trigger immediate DVT risk reassessment?',
    '["Reduced mobility with unilateral leg swelling","Seasonal rhinitis without systemic findings","Mild isolated headache","Stable appetite with no symptoms"]'::jsonb,
    0,
    'Reduced mobility and unilateral leg swelling are core DVT risk signals requiring immediate reassessment.',
    'VTE',
    array['guideline','treatment-perception']
  ),
  (
    'bbbbbbbb-0000-0000-0000-000000000002',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'Which analytics output best identifies VTE knowledge gaps for follow-up by region and facility?',
    '["Most-missed questions by region and facility","Presenter attendance log only","Venue seating chart","Session poster color preference"]'::jsonb,
    0,
    'Most-missed question clusters segmented by region and facility are the clearest signal for targeted follow-up.',
    'VTE',
    array['guideline']
  ),
  (
    'bbbbbbbb-0000-0000-0000-000000000003',
    'aaaaaaaa-0000-0000-0000-000000000002',
    'In infection stewardship education, what is the best first step before finalizing empirical therapy?',
    '["Collect culture and local susceptibility context","Skip indication documentation","Delay all therapy by default","Use broad therapy without review"]'::jsonb,
    0,
    'A culture-informed decision process with local susceptibility context supports safer, more appropriate use.',
    'UTI/Infections',
    array['guideline','treatment-perception']
  ),
  (
    'bbbbbbbb-0000-0000-0000-000000000004',
    'aaaaaaaa-0000-0000-0000-000000000002',
    'For live QR plus self-paced retries, which KPI pairing best measures learning lift?',
    '["First-attempt accuracy and retry improvement","Total slide count and venue size","Host speaking speed and attire","Number of coffee breaks"]'::jsonb,
    0,
    'Comparing first-attempt accuracy with retry improvement provides a direct measure of retained learning.',
    'UTI/Infections',
    array['guideline']
  )
on conflict (id) do nothing;

insert into app.sessions (id, quiz_id, name, join_code, host_name, starts_at, ends_at, metadata)
values
  (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'Korle Bu CME - VTE Master Class',
    'KBTH-CME-2026',
    'Dr. Kwame',
    '2026-05-17 09:00:00+00',
    '2026-05-17 12:00:00+00',
    '{"region":"Greater Accra","mode":"mixed","hostType":"cme"}'::jsonb
  )
on conflict (id) do nothing;

insert into app.attempts (
  id,
  user_id,
  quiz_id,
  session_id,
  mode,
  origin,
  score,
  total_questions,
  time_taken_ms,
  season_key,
  started_at,
  completed_at,
  metadata
)
values
  (
    'cccccccc-0000-0000-0000-000000000001',
    '22222222-2222-2222-2222-222222222222',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'ranked',
    'qr_session',
    5,
    5,
    124000,
    '2026-05',
    '2026-05-17 09:10:00+00',
    '2026-05-17 09:12:04+00',
    '{"source":"live-session"}'::jsonb
  ),
  (
    'cccccccc-0000-0000-0000-000000000002',
    '33333333-3333-3333-3333-333333333333',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'ranked',
    'qr_session',
    4,
    5,
    143000,
    '2026-05',
    '2026-05-17 09:14:00+00',
    '2026-05-17 09:16:23+00',
    '{"source":"live-session"}'::jsonb
  ),
  (
    'cccccccc-0000-0000-0000-000000000003',
    '44444444-4444-4444-4444-444444444444',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'ranked',
    'qr_session',
    4,
    5,
    138000,
    '2026-05',
    '2026-05-17 09:18:00+00',
    '2026-05-17 09:20:18+00',
    '{"source":"live-session"}'::jsonb
  ),
  (
    'cccccccc-0000-0000-0000-000000000004',
    '11111111-1111-1111-1111-111111111111',
    'aaaaaaaa-0000-0000-0000-000000000002',
    null,
    'ranked',
    'open_access',
    4,
    5,
    105000,
    '2026-05',
    '2026-05-18 19:00:00+00',
    '2026-05-18 19:01:45+00',
    '{"source":"self-paced"}'::jsonb
  ),
  (
    'cccccccc-0000-0000-0000-000000000005',
    '11111111-1111-1111-1111-111111111111',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'learning',
    'qr_session',
    3,
    5,
    165000,
    '2026-05',
    '2026-05-17 09:30:00+00',
    '2026-05-17 09:32:45+00',
    '{"source":"live-session-retry"}'::jsonb
  ),
  (
    'cccccccc-0000-0000-0000-000000000006',
    '11111111-1111-1111-1111-111111111111',
    'aaaaaaaa-0000-0000-0000-000000000001',
    null,
    'learning',
    'open_access',
    5,
    5,
    118000,
    '2026-05',
    '2026-05-18 20:10:00+00',
    '2026-05-18 20:11:58+00',
    '{"source":"self-paced-retry"}'::jsonb
  )
on conflict (id) do nothing;

insert into app.answers (attempt_id, question_id, selected_index, selected_option_text, is_correct, response_time_ms)
values
  ('cccccccc-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 0, 'Reduced mobility with unilateral leg swelling', true, 22000),
  ('cccccccc-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002', 0, 'Most-missed questions by region and facility', true, 24000),
  ('cccccccc-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000001', 1, 'Seasonal rhinitis without systemic findings', false, 30000),
  ('cccccccc-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000002', 0, 'Most-missed questions by region and facility', true, 18000),
  ('cccccccc-0000-0000-0000-000000000003', 'bbbbbbbb-0000-0000-0000-000000000001', 0, 'Reduced mobility with unilateral leg swelling', true, 19000),
  ('cccccccc-0000-0000-0000-000000000003', 'bbbbbbbb-0000-0000-0000-000000000002', 1, 'Presenter attendance log only', false, 28000),
  ('cccccccc-0000-0000-0000-000000000004', 'bbbbbbbb-0000-0000-0000-000000000003', 1, 'Skip indication documentation', false, 21000),
  ('cccccccc-0000-0000-0000-000000000004', 'bbbbbbbb-0000-0000-0000-000000000004', 0, 'First-attempt accuracy and retry improvement', true, 18000),
  ('cccccccc-0000-0000-0000-000000000005', 'bbbbbbbb-0000-0000-0000-000000000001', 1, 'Seasonal rhinitis without systemic findings', false, 33000),
  ('cccccccc-0000-0000-0000-000000000005', 'bbbbbbbb-0000-0000-0000-000000000002', 1, 'Presenter attendance log only', false, 26000),
  ('cccccccc-0000-0000-0000-000000000006', 'bbbbbbbb-0000-0000-0000-000000000001', 0, 'Reduced mobility with unilateral leg swelling', true, 20000),
  ('cccccccc-0000-0000-0000-000000000006', 'bbbbbbbb-0000-0000-0000-000000000002', 0, 'Most-missed questions by region and facility', true, 17000)
on conflict (attempt_id, question_id) do nothing;
