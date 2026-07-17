# ข้อ 2: Complex SQL — Doctor Availability

## วิธีที่ผมใช้

ผมเริ่มจากกำหนดช่วงเวลาที่ต้องการหาแพทย์เป็น 10:00–11:00 ของวันที่ 19 มีนาคม 2026 แล้วตัดแพทย์ออกสองกรณี:

1. มีนัดสถานะ `confirmed` ที่เวลาทับกับช่วงนี้
2. มีช่วงพักใน `doctor_shifts` ที่เวลาทับกับช่วงนี้

ผมใช้ `NOT EXISTS` เพราะสิ่งที่ต้องการคือเช็กว่าไม่มีข้อมูลที่ชนกับช่วงเวลา ไม่ต้อง join รายการนัดทั้งหมดออกมา และไม่ทำให้รายชื่อแพทย์ซ้ำเมื่อแพทย์มีหลายรายการ

## Schema ที่ผมสมมติ

- `doctors(id, name, is_active)`
- `appointments(id, doctor_id, status, start_time, end_time)`
- `doctor_shifts(id, doctor_id, shift_type, start_time, end_time)`
- ช่วงพักใช้ `shift_type = 'break'`
- `start_time` และ `end_time` ใช้ PostgreSQL `TIMESTAMPTZ`

## เงื่อนไขเวลาทับซ้อน

ผมใช้ช่วงเวลาแบบครึ่งเปิด `[start, end)` และเช็ก overlap ด้วยเงื่อนไขนี้:

```sql
existing_start < requested_end
AND existing_end > requested_start
```

ดังนั้น:

- นัด 09:30–10:15 ถือว่าทับ เพราะกินเวลาล้ำเข้ามาหลัง 10:00
- นัด 10:30–11:30 ถือว่าทับ
- นัดที่จบตรง 10:00 ไม่ทับ และแพทย์เริ่มรับงานใหม่ตอน 10:00 ได้
- นัดที่เริ่มตรง 11:00 ไม่ทับ

## SQL

โค้ดด้านล่างตรงกับไฟล์ [`02-doctor-availability.sql`](02-doctor-availability.sql) ทั้งหมด

```sql
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
```

## ทำไม query นี้รองรับนัดที่ล้ำมาจากก่อน 10:00

ผมไม่ได้เช็กเฉพาะนัดที่ `start_time` อยู่ระหว่าง 10:00–11:00 เพราะจะพลาดนัดอย่าง 09:30–10:15 เงื่อนไข overlap จะดูทั้งเวลาเริ่มและเวลาจบ จึงครอบคลุมทั้งนัดที่เริ่มก่อน ช่วงที่อยู่ข้างใน และนัดที่ลากยาวเกิน 11:00

ผมเพิ่ม partial index เฉพาะ `confirmed` appointment และช่วง `break` เพราะเป็นข้อมูลที่ query นี้ค้นจริง ช่วยลดจำนวนแถวที่ PostgreSQL ต้องตรวจเมื่อข้อมูลมีขนาดใหญ่

ชุดทดสอบ PostgreSQL อยู่ใน [`02-doctor-availability.test.sql`](02-doctor-availability.test.sql) โดยใช้ temporary tables และ rollback หลังทดสอบ จึงไม่แก้ข้อมูลจริง
