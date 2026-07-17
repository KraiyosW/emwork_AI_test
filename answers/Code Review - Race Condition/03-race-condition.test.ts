import {
  claimInsurance,
  PatientNotFoundError,
  type DatabaseClient,
  type DatabasePool,
  type QueryResult,
} from './03-race-condition.ts';

interface ExpectedQuery {
  includes: string;
  params?: readonly unknown[];
  result?: QueryResult<unknown>;
  error?: Error;
}

const normalizeSql = (sql: string): string => sql.replace(/\s+/g, ' ').trim();

const assert = (condition: boolean, message: string): void => {
  if (!condition) {
    throw new Error(message);
  }
};

const assertEqual = <T>(actual: T, expected: T, message: string): void => {
  assert(
    Object.is(actual, expected),
    `${message}: expected ${String(expected)}, received ${String(actual)}`,
  );
};

const emptyResult = (): QueryResult<unknown> => ({ rows: [], rowCount: null });

class MockClient implements DatabaseClient {
  public released = false;
  public readonly calls: Array<{ sql: string; params: readonly unknown[] }> = [];
  private readonly expectedQueries: ExpectedQuery[];

  public constructor(expectedQueries: ExpectedQuery[]) {
    this.expectedQueries = expectedQueries;
  }

  public async query<Row = Record<string, unknown>>(
    sql: string,
    params: readonly unknown[] = [],
  ): Promise<QueryResult<Row>> {
    const expected = this.expectedQueries.shift();

    if (!expected) {
      throw new Error(`Unexpected query: ${normalizeSql(sql)}`);
    }

    const normalizedSql = normalizeSql(sql);
    this.calls.push({ sql: normalizedSql, params });

    assert(
      normalizedSql.includes(expected.includes),
      `Expected SQL to include "${expected.includes}", received "${normalizedSql}"`,
    );
    assertEqual(
      JSON.stringify(params),
      JSON.stringify(expected.params ?? []),
      'query parameters',
    );

    if (expected.error) {
      throw expected.error;
    }

    return (expected.result ?? emptyResult()) as QueryResult<Row>;
  }

  public release(): void {
    this.released = true;
  }

  public assertComplete(): void {
    assertEqual(this.expectedQueries.length, 0, 'unconsumed expected queries');
    assert(this.released, 'database client must be released');
  }
}

class MockPool implements DatabasePool {
  public connectCount = 0;
  private readonly client: DatabaseClient;

  public constructor(client: DatabaseClient) {
    this.client = client;
  }

  public async connect(): Promise<DatabaseClient> {
    this.connectCount += 1;
    return this.client;
  }
}

const tests: ReadonlyArray<readonly [string, () => Promise<void>]> = [
  [
    'locks the row and commits a successful claim',
    async () => {
      const maliciousId = "P001'; DROP TABLE patients; --";
      const client = new MockClient([
        { includes: 'BEGIN' },
        {
          includes: 'WHERE id = $1 FOR UPDATE',
          params: [maliciousId],
          result: {
            rows: [{ insurance_limit: '10000' }],
            rowCount: 1,
          },
        },
        {
          includes: 'SET insurance_limit = insurance_limit - $1',
          params: ['3000', maliciousId],
          result: {
            rows: [{ insurance_limit: '7000' }],
            rowCount: 1,
          },
        },
        { includes: 'COMMIT' },
      ]);

      const result = await claimInsurance(
        new MockPool(client),
        maliciousId,
        3_000n,
      );

      assertEqual(result, true, 'successful claim');
      assert(
        !client.calls.some(({ sql }) => sql.includes(maliciousId)),
        'patientId must not be interpolated into SQL',
      );
      client.assertComplete();
    },
  ],
  [
    'rolls back when the insurance limit is insufficient',
    async () => {
      const client = new MockClient([
        { includes: 'BEGIN' },
        {
          includes: 'FOR UPDATE',
          params: ['P002'],
          result: {
            rows: [{ insurance_limit: '2000' }],
            rowCount: 1,
          },
        },
        { includes: 'ROLLBACK' },
      ]);

      const result = await claimInsurance(
        new MockPool(client),
        'P002',
        3_000n,
      );

      assertEqual(result, false, 'insufficient insurance claim');
      client.assertComplete();
    },
  ],
  [
    'rolls back and throws when the patient does not exist',
    async () => {
      const client = new MockClient([
        { includes: 'BEGIN' },
        {
          includes: 'FOR UPDATE',
          params: ['missing'],
          result: { rows: [], rowCount: 0 },
        },
        { includes: 'ROLLBACK' },
      ]);

      let receivedError: unknown;

      try {
        await claimInsurance(new MockPool(client), 'missing', 1_000n);
      } catch (error) {
        receivedError = error;
      }

      assert(
        receivedError instanceof PatientNotFoundError,
        'missing patient must throw PatientNotFoundError',
      );
      client.assertComplete();
    },
  ],
  [
    'rolls back when the update fails',
    async () => {
      const updateError = new Error('database update failed');
      const client = new MockClient([
        { includes: 'BEGIN' },
        {
          includes: 'FOR UPDATE',
          params: ['P003'],
          result: {
            rows: [{ insurance_limit: '5000' }],
            rowCount: 1,
          },
        },
        {
          includes: 'UPDATE patients',
          params: ['1000', 'P003'],
          error: updateError,
        },
        { includes: 'ROLLBACK' },
      ]);

      let receivedError: unknown;

      try {
        await claimInsurance(new MockPool(client), 'P003', 1_000n);
      } catch (error) {
        receivedError = error;
      }

      assertEqual(receivedError, updateError, 'update error');
      client.assertComplete();
    },
  ],
  [
    'rejects an invalid cost before opening a connection',
    async () => {
      const client = new MockClient([]);
      const pool = new MockPool(client);
      let receivedError: unknown;

      try {
        await claimInsurance(pool, 'P004', 0n);
      } catch (error) {
        receivedError = error;
      }

      assert(receivedError instanceof RangeError, 'invalid cost must throw');
      assertEqual(pool.connectCount, 0, 'database connection count');
    },
  ],
];

for (const [name, run] of tests) {
  await run();
  console.log(`✓ ${name}`);
}

console.log(`\n${tests.length} race condition tests passed`);
