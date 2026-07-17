import {
  getUrgentPatient,
  type Patient,
} from './01-priority-queue.ts';

const NOW = '2026-03-19T11:00:00+07:00';

const patient = (
  id: string,
  type: Patient['type'],
  severity: number,
  queuedAt: string,
): Patient => ({ id, type, severity, queuedAt });

const assertEqual = <T>(actual: T, expected: T, message: string): void => {
  if (!Object.is(actual, expected)) {
    throw new Error(`${message}: expected ${String(expected)}, received ${String(actual)}`);
  }
};

const assertThrows = (callback: () => unknown, message: string): void => {
  let didThrow = false;

  try {
    callback();
  } catch {
    didThrow = true;
  }

  if (!didThrow) {
    throw new Error(`${message}: expected the function to throw`);
  }
};

const tests: ReadonlyArray<readonly [string, () => void]> = [
  [
    'returns null for an empty queue',
    () => assertEqual(getUrgentPatient([], NOW), null, 'empty queue'),
  ],
  [
    'prioritizes Emergency over an unpromoted Normal patient',
    () => {
      const result = getUrgentPatient([
        patient('normal', 'N', 10, '2026-03-19T10:30:00+07:00'),
        patient('emergency', 'E', 1, '2026-03-19T10:59:00+07:00'),
      ], NOW);

      assertEqual(result?.id, 'emergency', 'Emergency priority');
    },
  ],
  [
    'uses higher severity within the same priority class',
    () => {
      const result = getUrgentPatient([
        patient('severity-5', 'E', 5, '2026-03-19T10:50:00+07:00'),
        patient('severity-9', 'E', 9, '2026-03-19T10:55:00+07:00'),
      ], NOW);

      assertEqual(result?.id, 'severity-9', 'severity comparison');
    },
  ],
  [
    'promotes a Normal patient at the 60-minute boundary',
    () => {
      const result = getUrgentPatient([
        patient('emergency', 'E', 7, '2026-03-19T10:55:00+07:00'),
        patient('promoted-normal', 'N', 8, '2026-03-19T10:00:00+07:00'),
      ], NOW);

      assertEqual(result?.id, 'promoted-normal', '60-minute promotion');
    },
  ],
  [
    'does not promote a Normal patient before 60 minutes',
    () => {
      const result = getUrgentPatient([
        patient('emergency', 'E', 1, '2026-03-19T10:59:00+07:00'),
        patient('normal', 'N', 10, '2026-03-19T10:00:01+07:00'),
      ], NOW);

      assertEqual(result?.id, 'emergency', 'before promotion threshold');
    },
  ],
  [
    'uses FIFO when priority and severity are equal',
    () => {
      const result = getUrgentPatient([
        patient('later', 'E', 7, '2026-03-19T10:55:00+07:00'),
        patient('earlier', 'E', 7, '2026-03-19T10:50:00+07:00'),
      ], NOW);

      assertEqual(result?.id, 'earlier', 'FIFO tie-break');
    },
  ],
  [
    'does not mutate the input queue',
    () => {
      const queue = [
        patient('normal', 'N', 5, '2026-03-19T10:30:00+07:00'),
        patient('emergency', 'E', 5, '2026-03-19T10:50:00+07:00'),
      ];
      const snapshot = JSON.stringify(queue);

      getUrgentPatient(queue, NOW);

      assertEqual(JSON.stringify(queue), snapshot, 'queue mutation');
    },
  ],
  [
    'rejects severity outside the range 1-10',
    () => assertThrows(
      () => getUrgentPatient([
        patient('invalid', 'N', 11, '2026-03-19T10:30:00+07:00'),
      ], NOW),
      'invalid severity',
    ),
  ],
  [
    'rejects invalid dates',
    () => assertThrows(
      () => getUrgentPatient([
        patient('invalid', 'N', 5, 'not-a-date'),
      ], NOW),
      'invalid queuedAt',
    ),
  ],
];

for (const [name, run] of tests) {
  run();
  console.log(`✓ ${name}`);
}

console.log(`\n${tests.length} priority queue tests passed`);
