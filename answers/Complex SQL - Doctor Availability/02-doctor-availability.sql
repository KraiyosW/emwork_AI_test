WITH requested_slot AS (
  SELECT
    TIMESTAMPTZ '2026-03-19 10:00:00+07:00' AS start_time,
    TIMESTAMPTZ '2026-03-19 11:00:00+07:00' AS end_time
)
SELECT
  d.id,
  d.name
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
ORDER BY d.name;

CREATE INDEX IF NOT EXISTS idx_appointments_confirmed_doctor_time
  ON appointments (doctor_id, start_time, end_time)
  WHERE status = 'confirmed';

CREATE INDEX IF NOT EXISTS idx_doctor_shifts_break_doctor_time
  ON doctor_shifts (doctor_id, start_time, end_time)
  WHERE shift_type = 'break';
