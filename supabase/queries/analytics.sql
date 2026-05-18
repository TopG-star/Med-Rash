-- Highest-priority knowledge gaps across all participants.
select *
from app.knowledge_gaps(10);

-- Knowledge gaps for a specialty segment.
select *
from app.knowledge_gaps(10, specialty_filter => 'Emergency Medicine');

-- Knowledge gaps for a single facility.
select *
from app.knowledge_gaps(10, facility_filter => 'Korle-Bu Teaching Hospital');

-- Knowledge gaps within a live session.
select *
from app.knowledge_gaps(
  10,
  session_filter => 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
);

-- Facilities ordered by weakest average performance first.
select *
from app.facility_performance(20);

-- Treatment perception signals from tagged questions.
select *
from app.treatment_perception_trends(10);