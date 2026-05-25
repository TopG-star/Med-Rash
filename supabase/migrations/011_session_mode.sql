-- Gap 6: host-declared session mode.
--
-- Until now the participant lobby asked Ranked-vs-Learning every time, even
-- when the host already knew the intent (formal CME vs study group). This
-- column lets the host pick once at session creation; the Flutter lobby
-- then renders a single primary CTA. Default 'ranked' preserves the
-- historical behaviour for sessions created before this migration ran.

alter table app.sessions
  add column if not exists mode text not null default 'ranked'
    check (mode in ('ranked', 'learning'));
