# ข้อ 3: Code Review — The Race Condition

## ปัญหาในโค้ดเดิม

ผมเห็นปัญหาหลักสองจุดตามโจทย์

### 1. SQL Injection

โค้ดเดิมนำ `patientId` และ `newLimit` ไปต่อใน SQL โดยตรง ถ้ามีค่าที่ถูกสร้างมาเพื่อเปลี่ยนคำสั่ง SQL ก็อาจกระทบข้อมูลในฐานข้อมูลได้ ผมแก้ด้วย parameterized query โดยใช้ `$1` และ `$2` และส่งค่าผ่าน params แยกจาก SQL

### 2. Race Condition

โค้ดเดิมอ่านวงเงินและ update แยกกัน ถ้ามีสอง request เข้ามาพร้อมกัน ทั้งสอง request อาจอ่านวงเงินเดิมก่อนที่อีกฝั่งจะ update ทำให้ระบบอนุมัติวงเงินเกินจริง

ผมแก้ด้วย transaction และ `SELECT ... FOR UPDATE` เพื่อ lock row ของผู้ป่วย เมื่อ request แรกกำลังตรวจและหักวงเงิน request ที่สองต้องรอ แล้วจึงอ่านวงเงินล่าสุดหลังจาก request แรก commit หรือ rollback

## Assumptions

- ใช้ PostgreSQL และ connection pool รูปแบบเดียวกับ `pg`
- ตาราง `patients` มี `id` และ `insurance_limit`
- วงเงินเก็บเป็นจำนวนเต็มในหน่วยเล็กที่สุด เช่น สตางค์ เพื่อหลีกเลี่ยงปัญหา floating point
- ถ้าผู้ป่วยไม่มีอยู่จริง ให้ throw `PatientNotFoundError`
- ถ้าวงเงินไม่พอ ให้ rollback และคืน `false`

## Implementation

โค้ดด้านล่างตรงกับไฟล์ [`03-race-condition.ts`](03-race-condition.ts) ทั้งหมด

```ts
export interface QueryResult<Row> {
  rows: Row[];
  rowCount: number | null;
}

export interface DatabaseClient {
  query<Row = Record<string, unknown>>(
    sql: string,
    params?: readonly unknown[],
  ): Promise<QueryResult<Row>>;
  release(): void;
}

export interface DatabasePool {
  connect(): Promise<DatabaseClient>;
}

interface PatientInsuranceRow {
  insurance_limit: string;
}

interface UpdatedInsuranceRow {
  insurance_limit: string;
}

export class PatientNotFoundError extends Error {
  constructor(patientId: string) {
    super(`Patient ${patientId} was not found`);
    this.name = 'PatientNotFoundError';
  }
}

/**
 * Claims insurance in the smallest currency unit, such as satang.
 * The patient row stays locked until the transaction is committed or rolled back.
 */
export const claimInsurance = async (
  pool: DatabasePool,
  patientId: string,
  treatmentCost: bigint,
): Promise<boolean> => {
  if (patientId.trim() === '') {
    throw new TypeError('patientId must not be empty');
  }

  if (treatmentCost <= 0n) {
    throw new RangeError('treatmentCost must be greater than zero');
  }

  const client = await pool.connect();
  let transactionActive = false;

  try {
    await client.query('BEGIN');
    transactionActive = true;

    const patientResult = await client.query<PatientInsuranceRow>(
      `SELECT insurance_limit
       FROM patients
       WHERE id = $1
       FOR UPDATE`,
      [patientId],
    );

    const patient = patientResult.rows[0];

    if (!patient) {
      throw new PatientNotFoundError(patientId);
    }

    const currentLimit = BigInt(patient.insurance_limit);

    if (currentLimit < treatmentCost) {
      await client.query('ROLLBACK');
      transactionActive = false;
      return false;
    }

    await client.query<UpdatedInsuranceRow>(
      `UPDATE patients
       SET insurance_limit = insurance_limit - $1
       WHERE id = $2
       RETURNING insurance_limit`,
      [treatmentCost.toString(), patientId],
    );

    await client.query('COMMIT');
    transactionActive = false;
    return true;
  } catch (error) {
    if (transactionActive) {
      await client.query('ROLLBACK');
    }

    throw error;
  } finally {
    client.release();
  }
};
```

## ทำไม race condition ถึงหาย

`FOR UPDATE` จะ lock เฉพาะ row ของผู้ป่วยที่กำลังเคลม ไม่ได้ lock ทั้งตาราง สมมติมีวงเงิน 5,000 และมีสอง request ขอใช้ 3,000 พร้อมกัน:

1. Request A lock row และอ่านวงเงิน 5,000
2. Request B รอ lock
3. Request A หักเหลือ 2,000 และ commit
4. Request B ได้ lock แล้วอ่านค่าใหม่เป็น 2,000
5. Request B เห็นว่าวงเงินไม่พอ จึง rollback และคืน `false`

อีกจุดที่ผมตั้งใจทำคือให้ database คำนวณ `insurance_limit - $1` โดยตรงภายใน transaction แทนการคำนวณค่าใหม่ใน application แล้วส่งกลับไป update

## Verification

ชุดทดสอบอยู่ใน [`03-race-condition.test.ts`](03-race-condition.test.ts) ครอบคลุม successful claim, วงเงินไม่พอ, ไม่พบผู้ป่วย, update ล้มเหลว, rollback, release connection และตรวจว่า input ที่เป็น SQL injection ไม่ถูกนำไปต่อใน SQL

```bash
npm run typecheck
npm run test:race-condition
```
