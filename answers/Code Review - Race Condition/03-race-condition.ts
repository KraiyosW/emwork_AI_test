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
