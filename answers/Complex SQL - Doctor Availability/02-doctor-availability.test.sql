\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE doctors (
  id BIGINT PRIMARY KEY,
  name TEXT NOT NULL,
  is_active BOOLEAN NOT NULL
);

CREATE TEMP TABLE appointments (
  id BIGINT PRIMARY KEY,
  doctor_id BIGINT NOT NULL REFERENCES doctors (id),
  status TEXT NOT NULL,
  start_time TIMESTAMPTZ NOT NULL,
  end_time TIMESTAMPTZ NOT NULL
);

CREATE TEMP TABLE doctor_shifts (
  id BIGINT PRIMARY KEY,
  doctor_id BIGINT NOT NULL REFERENCES doctors (id),
  shift_type TEXT NOT NULL,
  start_time TIMESTAMPTZ NOT NULL,
  end_time TIMESTAMPTZ NOT NULL
);

INSERT INTO doctors (id, name, is_active) VALUES
  (1, 'Available', TRUE),
  (2, 'OverlapFromBefore', TRUE),
  (3, 'EndsAtStart', TRUE),
  (4, 'StartsAtEnd', TRUE),
  (5, 'PendingOverlap', TRUE),
  (6, 'OnBreak', TRUE),
  (7, 'Inactive', FALSE),
  (8, 'OverlapInside', TRUE);

INSERT INTO appointments (
  id,
  doctor_id,
  status,
  start_time,
  end_time
) VALUES
  (1, 2, 'confirmed', '2026-03-19 09:30:00+07:00', '2026-03-19 10:15:00+07:00'),
  (2, 3, 'confirmed', '2026-03-19 09:00:00+07:00', '2026-03-19 10:00:00+07:00'),
  (3, 4, 'confirmed', '2026-03-19 11:00:00+07:00', '2026-03-19 12:00:00+07:00'),
  (4, 5, 'pending', '2026-03-19 10:15:00+07:00', '2026-03-19 10:45:00+07:00'),
  (5, 8, 'confirmed', '2026-03-19 10:30:00+07:00', '2026-03-19 10:45:00+07:00');

INSERT INTO doctor_shifts (
  id,
  doctor_id,
  shift_type,
  start_time,
  end_time
) VALUES
  (1, 6, 'break', '2026-03-19 10:20:00+07:00', '2026-03-19 10:40:00+07:00');

\echo 'Running the submitted query:'
\ir 02-doctor-availability.sql

DO $$
DECLARE
  actual_names TEXT[];
  expected_names CONSTANT TEXT[] := ARRAY[
    'Available',
    'EndsAtStart',
    'PendingOverlap',
    'StartsAtEnd'
  ];
BEGIN
  WITH requested_slot AS (
    SELECT
      TIMESTAMPTZ '2026-03-19 10:00:00+07:00' AS start_time,
      TIMESTAMPTZ '2026-03-19 11:00:00+07:00' AS end_time
  ), available_doctors AS (
    SELECT d.name
    FROM doctors AS d
    CROSS JOIN requested_slot AS slot
    WHERE d.is_active = TRUE
      AND NOT EXISTS (
        SELECT 1
        FROM appointments AS a
        WHERE a.doctor_id = d.id
          AND a.status = 'confirmed'
          AND a.start_time < slot.end_time
          AND a.end_time > slot.start_time
      )
      AND NOT EXISTS (
        SELECT 1
        FROM doctor_shifts AS ds
        WHERE ds.doctor_id = d.id
          AND ds.shift_type = 'break'
          AND ds.start_time < slot.end_time
          AND ds.end_time > slot.start_time
      )
  )
  SELECT ARRAY_AGG(name ORDER BY name)
  INTO actual_names
  FROM available_doctors;

  IF actual_names IS DISTINCT FROM expected_names THEN
    RAISE EXCEPTION
      'Expected %, received %',
      expected_names,
      actual_names;
  END IF;
END
$$;

\echo 'PASS: all doctor availability cases returned the expected result'

ROLLBACK;
