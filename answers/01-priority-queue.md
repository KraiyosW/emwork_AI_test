# ข้อ 1: The Intelligent Priority Queue

## วิธีที่ผมใช้

ผมมอง priority เป็น 3 ขั้นตามโจทย์:

1. เช็กก่อนว่าเป็น Emergency หรือเป็น Normal ที่รอครบ 60 นาทีแล้วหรือยัง
2. ถ้า priority เท่ากัน ค่อยเทียบ severity โดยคะแนนสูงกว่ามาก่อน
3. ถ้ายังเท่ากันอีก ให้คนที่เข้าคิวก่อนมาก่อนแบบ FIFO

ผมสมมติว่า `type` และ `severity` ผ่านการประเมินจากเจ้าหน้าที่ triage มาแล้ว ฟังก์ชันนี้มีหน้าที่จัดลำดับอย่างเดียว ไม่ได้วิเคราะห์อาการหรือให้คะแนนผู้ป่วยเอง

สำหรับคำว่า “รอเกิน 60 นาที” ผมใช้ `>= 60 นาที` เพราะถือว่าเมื่อแตะ threshold แล้วให้เลื่อน priority ได้ทันที และเขียน assumption นี้ไว้ให้ชัดเจน

ตัวอย่างเช่น Emergency severity 7 เทียบกับ Normal severity 8 ที่รอมา 70 นาที ผมจะเลือก Normal ก่อน เพราะ Normal คนนั้นถูกเลื่อนมาอยู่ priority เดียวกับ Emergency แล้ว จากนั้นจึงตัดสินด้วย severity

## Implementation

โค้ดด้านล่างตรงกับไฟล์ [`01-priority-queue.ts`](01-priority-queue.ts) ทั้งหมด

```ts
const ONE_HOUR_MS = 60 * 60 * 1_000;

export type PatientType = 'E' | 'N';
export type DateInput = Date | string | number;

export interface Patient {
  id: string;
  type: PatientType;
  severity: number;
  queuedAt: DateInput;
}

interface PatientRank {
  effectivePriority: 0 | 1;
  severity: number;
  queuedAt: number;
}

const toTimestamp = (value: DateInput, fieldName: string): number => {
  const timestamp = value instanceof Date
    ? value.getTime()
    : new Date(value).getTime();

  if (!Number.isFinite(timestamp)) {
    throw new TypeError(`${fieldName} must be a valid date or timestamp`);
  }

  return timestamp;
};

const validatePatient = (patient: Patient): void => {
  if (!patient || typeof patient !== 'object') {
    throw new TypeError('Each patient must be an object');
  }

  if (patient.type !== 'E' && patient.type !== 'N') {
    throw new RangeError(`Patient ${patient.id ?? '(unknown)'} has an invalid type`);
  }

  if (
    !Number.isInteger(patient.severity)
    || patient.severity < 1
    || patient.severity > 10
  ) {
    throw new RangeError(
      `Patient ${patient.id ?? '(unknown)'} must have a severity from 1 to 10`,
    );
  }

  toTimestamp(patient.queuedAt, 'queuedAt');
};

/**
 * A Normal patient who has waited at least 60 minutes receives the same
 * effective priority class as an Emergency patient.
 */
const getRank = (
  patient: Patient,
  currentTimestamp: number,
): PatientRank => {
  const queuedAt = toTimestamp(patient.queuedAt, 'queuedAt');
  const waitingTimeMs = Math.max(0, currentTimestamp - queuedAt);
  const isPromotedNormal = patient.type === 'N'
    && waitingTimeMs >= ONE_HOUR_MS;

  return {
    effectivePriority: patient.type === 'E' || isPromotedNormal ? 1 : 0,
    severity: patient.severity,
    queuedAt,
  };
};

/**
 * Tie-break order: effective priority, severity, then queue time (FIFO).
 */
const isMoreUrgent = (
  candidate: Patient,
  selected: Patient,
  currentTimestamp: number,
): boolean => {
  const candidateRank = getRank(candidate, currentTimestamp);
  const selectedRank = getRank(selected, currentTimestamp);

  if (candidateRank.effectivePriority !== selectedRank.effectivePriority) {
    return candidateRank.effectivePriority > selectedRank.effectivePriority;
  }

  if (candidateRank.severity !== selectedRank.severity) {
    return candidateRank.severity > selectedRank.severity;
  }

  return candidateRank.queuedAt < selectedRank.queuedAt;
};

/**
 * Finds the next patient to receive treatment without mutating the queue.
 *
 * Time complexity: O(n)
 * Extra space: O(1)
 */
export const getUrgentPatient = (
  queue: readonly Patient[],
  currentTime: DateInput,
): Patient | null => {
  if (!Array.isArray(queue)) {
    throw new TypeError('queue must be an array');
  }

  if (queue.length === 0) {
    return null;
  }

  const currentTimestamp = toTimestamp(currentTime, 'currentTime');
  let selected: Patient | null = null;

  for (const patient of queue) {
    validatePatient(patient);

    if (
      selected === null
      || isMoreUrgent(patient, selected, currentTimestamp)
    ) {
      selected = patient;
    }
  }

  return selected;
};
```

## ทำไมผมเลือก `O(n)`

โจทย์ต้องการหาคนที่ควรได้รักษาเป็นคนถัดไปหนึ่งคน ผมจึงวนดูคิวรอบเดียวและเก็บคนที่ priority สูงที่สุดไว้ วิธีนี้เป็น `O(n)` และใช้พื้นที่เพิ่ม `O(1)`

ผมไม่เลือก sort ทั้งคิว เพราะจะกลายเป็น `O(n log n)` ทั้งที่เราต้องการแค่คนเดียว และไม่ใช้ heap ตัวเดียวเพราะ priority ของ Normal เปลี่ยนตาม `currentTime` ทำให้ข้อมูลใน heap อาจไม่เรียงถูกเมื่อเวลาผ่านไป

สำหรับผู้ป่วย 10,000 คน การวนหนึ่งรอบยังเบามากและเพียงพอกับโจทย์นี้ แต่ถ้าระบบต้องดึงผู้ป่วยออกจากคิวต่อเนื่องในปริมาณสูง ผมจะแยกโครงสร้างสำหรับ Emergency, Normal ที่ถูกเลื่อนแล้ว และ Normal ที่กำลังรอ เพื่อไม่ต้องสแกนทั้งคิวทุกครั้ง

## กรณีที่รองรับ

- คิวว่างจะคืน `null`
- type ต้องเป็น `E` หรือ `N`
- severity ต้องเป็นจำนวนเต็ม 1–10
- วันเวลาต้องแปลงเป็น timestamp ได้
- ถ้า `currentTime` อยู่ก่อน `queuedAt` จะนับเวลารอเป็นศูนย์
- ฟังก์ชันไม่แก้ไขคิวต้นฉบับ

ชุดทดสอบอยู่ใน [`01-priority-queue.test.ts`](01-priority-queue.test.ts) และตัวอย่างเรียกใช้อยู่ใน [`01-priority-queue.example.ts`](01-priority-queue.example.ts)

```bash
npm run typecheck
npm run test:priority
```
