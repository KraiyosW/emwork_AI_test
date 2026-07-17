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
