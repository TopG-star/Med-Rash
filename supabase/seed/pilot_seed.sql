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

insert into app.quizzes (id, slug, title, category, product, summary, question_count_default)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'clexane-vte-masterclass', 'Clexane In VTE: DVT And PE Management', 'VTE', 'Clexane', 'Live and post-session learning checks on DVT and PE risk recognition and management.', 5),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'tavanic-infection-stewardship', 'Tavanic In UTI And Respiratory Infections', 'UTI/Infections', 'Tavanic', 'Field-focused stewardship and treatment awareness checks for infection practice contexts.', 5),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'aprovel-hypertension-practice', 'Aprovel In Hypertension Practice', 'Hypertension', 'Aprovel', 'Applied hypertension treatment-awareness checks for mixed HCP audiences.', 5),
  ('aaaaaaaa-0000-0000-0000-000000000004', 'lantus-basal-diabetes-care', 'Lantus In Diabetes Basal Control', 'Diabetes', 'Lantus', 'Basal insulin practical knowledge checks for initiation and follow-up.', 5),
  ('aaaaaaaa-0000-0000-0000-000000000005', 'utrogestan-fertility-and-hormonal-care', 'Utrogestan Fertility And Hormonal Care', 'Fertility/Hormonal Imbalances', 'Utrogestan', 'Master class reinforcement on progesterone-support clinical pathways.', 5),
  ('aaaaaaaa-0000-0000-0000-000000000006', 'androgel-testosterone-deficiency-care', 'Androgel Testosterone Deficiency Care', 'Testosterone Deficiency', 'Androgel', 'Awareness and practice checks for testosterone-deficiency management contexts.', 5)
on conflict (id) do nothing;

insert into app.questions (id, quiz_id, prompt, options, correct_index, explanation, clinical_area, tags, position)
values
  -- ── Clexane: VTE ──────────────────────────────────────────────────────────────
  (
    'bbbbbbbb-0000-0000-0000-000000000001',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'In a VTE-focused master class, which signal should trigger immediate DVT risk reassessment?',
    '["Reduced mobility with unilateral leg swelling","Seasonal rhinitis without systemic findings","Mild isolated headache","Stable appetite with no symptoms"]'::jsonb,
    0,
    'Reduced mobility and unilateral leg swelling are core DVT risk signals requiring immediate reassessment.',
    'VTE', array['guideline','treatment-perception'], 0
  ),
  (
    'bbbbbbbb-0000-0000-0000-000000000002',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'Which analytics output best identifies VTE knowledge gaps for follow-up by region and facility?',
    '["Most-missed questions by region and facility","Presenter attendance log only","Venue seating chart","Session poster colour preference"]'::jsonb,
    0,
    'Most-missed question clusters segmented by region and facility are the clearest signal for targeted follow-up.',
    'VTE', array['guideline'], 1
  ),
  (
    'bbbbbbbb-0001-0000-0000-000000000003',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'During a hospital round, which patient profile warrants immediate VTE risk re-evaluation?',
    '["Reduced mobility with new unilateral leg swelling","Mild seasonal rhinitis only","Stable vision without pain","Isolated dry skin complaint"]'::jsonb,
    0,
    'Immobility and unilateral swelling are high-priority flags in DVT risk assessment.',
    'VTE', array['guideline'], 2
  ),
  (
    'bbbbbbbb-0001-0000-0000-000000000004',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'What is the best interpretation when session participation is high but quiz completion is low?',
    '["Onboarding worked but quiz experience or timing needs optimisation","No interest in the topic at all","Data capture should be disabled","Leaderboard should be removed immediately"]'::jsonb,
    0,
    'High starts with low finishes usually signals a UX, session pacing, or question-length issue.',
    'VTE', array['guideline'], 3
  ),
  (
    'bbbbbbbb-0001-0000-0000-000000000005',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'Which management view best supports resource allocation for future VTE education?',
    '["Region and facility heatmap of awareness gaps","List of random participant nicknames only","Session title alphabetical order","Average projector brightness"]'::jsonb,
    0,
    'Heatmaps make gap concentration obvious and actionable for planning next interventions.',
    'VTE', array['guideline'], 4
  ),
  -- ── Tavanic: UTI / Infections ──────────────────────────────────────────────────
  (
    'bbbbbbbb-0000-0000-0000-000000000003',
    'aaaaaaaa-0000-0000-0000-000000000002',
    'In infection stewardship education, what is the best first step before finalising empirical therapy?',
    '["Collect culture and local susceptibility context","Skip indication documentation","Delay all therapy by default","Use broad therapy without review"]'::jsonb,
    0,
    'A culture-informed decision process with local susceptibility context supports safer, more appropriate use.',
    'UTI/Infections', array['guideline','treatment-perception'], 0
  ),
  (
    'bbbbbbbb-0000-0000-0000-000000000004',
    'aaaaaaaa-0000-0000-0000-000000000002',
    'For live QR plus self-paced retries, which KPI pairing best measures learning lift?',
    '["First-attempt accuracy and retry improvement","Total slide count and venue size","Host speaking speed and attire","Number of coffee breaks"]'::jsonb,
    0,
    'Comparing first-attempt accuracy with retry improvement provides a direct measure of retained learning.',
    'UTI/Infections', array['guideline'], 1
  ),
  (
    'bbbbbbbb-0002-0000-0000-000000000003',
    'aaaaaaaa-0000-0000-0000-000000000002',
    'Which stewardship action best supports preserving fluoroquinolone effectiveness in practice?',
    '["Use only when clinical indication and guideline context align","Prescribe for all low-risk viral symptoms","Avoid documenting indication in notes","Skip follow-up once symptoms improve"]'::jsonb,
    0,
    'Clear indication, documentation, and follow-up are central to antimicrobial stewardship.',
    'UTI/Infections', array['guideline'], 2
  ),
  (
    'bbbbbbbb-0002-0000-0000-000000000004',
    'aaaaaaaa-0000-0000-0000-000000000002',
    'During a post-CME audit, which metric most directly signals a product knowledge gap?',
    '["Most-missed question clusters by facility and specialty","Only the number of slide views","The colour theme used in presentation","Average meeting duration alone"]'::jsonb,
    0,
    'Missed-question clusters reveal specific knowledge deficiencies tied to audience segments.',
    'UTI/Infections', array['guideline'], 3
  ),
  (
    'bbbbbbbb-0002-0000-0000-000000000005',
    'aaaaaaaa-0000-0000-0000-000000000002',
    'Which region-level signal best identifies where awareness reinforcement is needed first?',
    '["Lowest completion-adjusted score by disease area","Highest number of parking slots at facilities","Largest conference room in the region","Most social media followers of staff"]'::jsonb,
    0,
    'Completion-adjusted regional scores avoid bias from low participation and better target interventions.',
    'UTI/Infections', array['guideline'], 4
  ),
  -- ── Aprovel: Hypertension ──────────────────────────────────────────────────────
  (
    'bbbbbbbb-0003-0000-0000-000000000001',
    'aaaaaaaa-0000-0000-0000-000000000003',
    'In a hypertension CME, which patient profile most strongly warrants ARB therapy consideration?',
    '["High cardiovascular risk with early renal signs in a diabetic patient","Low-risk young adult with no comorbidities","Patient presenting with viral rhinitis alone","Stable patient who has declined all medication"]'::jsonb,
    0,
    'ARBs like irbesartan provide dual benefit — BP control and renal protection — in high-risk diabetic patients.',
    'Hypertension', array['guideline','treatment-perception'], 0
  ),
  (
    'bbbbbbbb-0003-0000-0000-000000000002',
    'aaaaaaaa-0000-0000-0000-000000000003',
    'Which outcome best demonstrates retained clinical learning from a hypertension education session?',
    '["Correct risk stratification on case-based scenarios","Increased prescribing without documentation","Generic treatment decisions without patient stratification","Repeating guideline numbers without clinical context"]'::jsonb,
    0,
    'Applied case-based accuracy is the clearest indicator of actionable knowledge retention.',
    'Hypertension', array['guideline'], 1
  ),
  (
    'bbbbbbbb-0003-0000-0000-000000000003',
    'aaaaaaaa-0000-0000-0000-000000000003',
    'For management analytics, which comparison best identifies where hypertension awareness investment is most needed?',
    '["Region-level gap in guideline-adherent management decisions","Total number of HCPs attending the session","Session room temperature and seating arrangement","Duration of opening presentations"]'::jsonb,
    0,
    'Regional management gap data guides prioritisation of educational and detailing resources.',
    'Hypertension', array['guideline'], 2
  ),
  (
    'bbbbbbbb-0003-0000-0000-000000000004',
    'aaaaaaaa-0000-0000-0000-000000000003',
    'What is the most evidence-aligned rationale for combining renal endpoints with BP metrics in hypertension analytics?',
    '["BP control alone understates clinical benefit in diabetic patients","Renal data is only relevant for nephrologists","BP outcomes are always sufficient without renal context","Renal metrics are only for research studies"]'::jsonb,
    0,
    'In diabetic hypertension, renal endpoints provide critical complementary data about long-term outcome benefit.',
    'Hypertension', array['guideline'], 3
  ),
  (
    'bbbbbbbb-0003-0000-0000-000000000005',
    'aaaaaaaa-0000-0000-0000-000000000003',
    'Which session design element most improves clinical decision-making recall in mixed specialty audiences?',
    '["Case vignettes with embedded decision checkpoints","Memorisation drills for generic numbers","Slide count and visual density alone","Duration and presenter credentials alone"]'::jsonb,
    0,
    'Case-based learning with embedded decision points strengthens clinical application and recall.',
    'Hypertension', array['guideline'], 4
  ),
  -- ── Lantus: Diabetes ──────────────────────────────────────────────────────────
  (
    'bbbbbbbb-0004-0000-0000-000000000001',
    'aaaaaaaa-0000-0000-0000-000000000004',
    'In basal insulin education, which outcome best reflects practical understanding after CME?',
    '["Correct titration decision in case-based questions","Memorising product logo details","Reciting event agenda from memory","Remembering meeting snack options"]'::jsonb,
    0,
    'Case-based titration decisions reflect applied clinical understanding.',
    'Diabetes', array['guideline','treatment-perception'], 0
  ),
  (
    'bbbbbbbb-0004-0000-0000-000000000002',
    'aaaaaaaa-0000-0000-0000-000000000004',
    'What is the strongest indicator of behaviour-oriented learning retention from a diabetes CME?',
    '["Improved retry scores with lower completion time","More profile picture updates","Higher Wi-Fi signal strength","Longer question stems"]'::jsonb,
    0,
    'Faster, more accurate retries suggest concepts are being internalised.',
    'Diabetes', array['guideline'], 1
  ),
  (
    'bbbbbbbb-0004-0000-0000-000000000003',
    'aaaaaaaa-0000-0000-0000-000000000004',
    'Which dataset is most useful for identifying diabetes-topic misconceptions by clinical cadre?',
    '["Answer-level incorrect patterns by role and specialty","Only total attendance counts","Only number of sessions run","Only nickname edit frequency"]'::jsonb,
    0,
    'Answer-level analysis reveals exactly where each cadre struggles.',
    'Diabetes', array['guideline'], 2
  ),
  (
    'bbbbbbbb-0004-0000-0000-000000000004',
    'aaaaaaaa-0000-0000-0000-000000000004',
    'If one region shows low awareness and low activity, what is the best next action?',
    '["Schedule a targeted session and monitor completion lift","Ignore the region until quarter-end","Disable the leaderboard globally","Pause all quizzes in other regions"]'::jsonb,
    0,
    'Focused intervention plus measurable lift tracking is the strongest response pattern.',
    'Diabetes', array['guideline'], 3
  ),
  (
    'bbbbbbbb-0004-0000-0000-000000000005',
    'aaaaaaaa-0000-0000-0000-000000000004',
    'Which KPI pairing should be reviewed together for fair performance interpretation?',
    '["Completion rate and score distribution by quiz mode","Host name and background music style","Phone model and wallpaper image","Slide count and venue AC temperature"]'::jsonb,
    0,
    'Completion and score distribution together prevent misleading single-metric conclusions.',
    'Diabetes', array['guideline'], 4
  ),
  -- ── Utrogestan: Fertility / Hormonal ──────────────────────────────────────────
  (
    'bbbbbbbb-0005-0000-0000-000000000001',
    'aaaaaaaa-0000-0000-0000-000000000005',
    'In luteal phase support, which clinical indicator should trigger consideration of progesterone supplementation?',
    '["Inadequate luteal phase length or low progesterone in a high-risk fertility case","Normal ovulation confirmed with no additional symptoms","Mild stress unrelated to hormonal profile","A single normal progesterone reading without clinical context"]'::jsonb,
    0,
    'Luteal phase inadequacy is a key indication for progesterone support in fertility management.',
    'Fertility/Hormonal Imbalances', array['guideline','treatment-perception'], 0
  ),
  (
    'bbbbbbbb-0005-0000-0000-000000000002',
    'aaaaaaaa-0000-0000-0000-000000000005',
    'What is the key clinical advantage of micronised progesterone in hormonal support therapy?',
    '["Improved tolerability and pharmacokinetic profile versus synthetic progestins","Identical clinical profile to synthetic progestins","Primarily a cost advantage without clinical differentiation","No practical difference from other progestogen options"]'::jsonb,
    0,
    'Micronised progesterone offers a profile closer to endogenous progesterone with better tolerability in oral and vaginal forms.',
    'Fertility/Hormonal Imbalances', array['guideline'], 1
  ),
  (
    'bbbbbbbb-0005-0000-0000-000000000003',
    'aaaaaaaa-0000-0000-0000-000000000005',
    'Which analytics output best identifies where fertility and hormonal care education has the greatest unmet need?',
    '["Specialty-segmented knowledge gap patterns from case-based questions","Number of participants who collected printed materials","Average meeting duration by region","Session background music preference"]'::jsonb,
    0,
    'Specialty-level gap analysis reveals where clinical knowledge needs targeted reinforcement.',
    'Fertility/Hormonal Imbalances', array['guideline'], 2
  ),
  (
    'bbbbbbbb-0005-0000-0000-000000000004',
    'aaaaaaaa-0000-0000-0000-000000000005',
    'For a CME session on hormonal management, which knowledge check design best evaluates clinical reasoning?',
    '["Patient pathway questions requiring integrated decision-making","Factual recall only without clinical scenarios","Questions on irrelevant administrative topics","Generic endocrinology trivia without clinical context"]'::jsonb,
    0,
    'Integrated clinical pathway questions assess whether participants can apply knowledge to actual patient care decisions.',
    'Fertility/Hormonal Imbalances', array['guideline'], 3
  ),
  (
    'bbbbbbbb-0005-0000-0000-000000000005',
    'aaaaaaaa-0000-0000-0000-000000000005',
    'Which post-session follow-up most effectively strengthens progesterone therapy practice?',
    '["Targeted case-based reinforcement based on missed question analysis","Repeat of the opening slide deck only","General newsletter without learning gap context","Administrative survey without clinical content"]'::jsonb,
    0,
    'Gaps identified from quiz analysis allow follow-up to be precisely targeted to knowledge deficiencies.',
    'Fertility/Hormonal Imbalances', array['guideline'], 4
  ),
  -- ── Androgel: Testosterone Deficiency ─────────────────────────────────────────
  (
    'bbbbbbbb-0006-0000-0000-000000000001',
    'aaaaaaaa-0000-0000-0000-000000000006',
    'In testosterone deficiency screening, which symptom cluster should most strongly prompt formal evaluation?',
    '["Fatigue, reduced libido, and loss of muscle mass in a middle-aged male","Isolated seasonal mood variation without physical symptoms","Single episode of fatigue after acute illness","Brief energy dip without other associated symptoms"]'::jsonb,
    0,
    'The combination of physical and functional symptoms forms the core clinical presentation warranting testosterone evaluation.',
    'Testosterone Deficiency', array['guideline','treatment-perception'], 0
  ),
  (
    'bbbbbbbb-0006-0000-0000-000000000002',
    'aaaaaaaa-0000-0000-0000-000000000006',
    'Which clinical endpoint pairing best evaluates testosterone therapy outcomes in practice?',
    '["Symptom score improvement and objective metabolic markers","Prescription count without patient outcome data","Number of prescriber visits alone","Product name recall by patients"]'::jsonb,
    0,
    'Combined symptom and metabolic assessment provides a holistic picture of testosterone therapy benefit.',
    'Testosterone Deficiency', array['guideline'], 1
  ),
  (
    'bbbbbbbb-0006-0000-0000-000000000003',
    'aaaaaaaa-0000-0000-0000-000000000006',
    'Which pattern in a post-CME knowledge check best indicates that testosterone deficiency education was effective?',
    '["Correct identification of evaluation thresholds and treatment endpoints in case scenarios","High attendance with no quiz completion","Participants requesting product samples only","Random answer patterns with high completion time"]'::jsonb,
    0,
    'Accurate case-based responses demonstrate that clinical learning translates to practice-relevant decision-making.',
    'Testosterone Deficiency', array['guideline'], 2
  ),
  (
    'bbbbbbbb-0006-0000-0000-000000000004',
    'aaaaaaaa-0000-0000-0000-000000000006',
    'Which management consideration most distinguishes testosterone deficiency care from general wellness supplementation?',
    '["Formal diagnosis with baseline labs and ongoing monitoring","Treatment based on patient self-report alone","No monitoring required after initiation","Short-term use only without reassessment"]'::jsonb,
    0,
    'Structured diagnosis and monitoring ensure both efficacy and patient safety throughout therapy.',
    'Testosterone Deficiency', array['guideline'], 3
  ),
  (
    'bbbbbbbb-0006-0000-0000-000000000005',
    'aaaaaaaa-0000-0000-0000-000000000006',
    'For a field force analytics platform, which output most accurately identifies region-level testosterone deficiency awareness gaps?',
    '["Question-specific error rates by specialty and facility type","Total session duration by presenter","Product detail frequency only","Meeting attendee nationality distribution"]'::jsonb,
    0,
    'Question-level error analysis segmented by specialty and facility reveals actionable awareness gaps for follow-up planning.',
    'Testosterone Deficiency', array['guideline'], 4
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
