import {
  getUrgentPatient,
  type Patient,
} from './01-priority-queue.js';

const currentTime = new Date('2026-03-19T11:00:00+07:00');

const queue: Patient[] = [
  {
    id: 'P001',
    type: 'N',
    severity: 10,
    queuedAt: '2026-03-19T10:30:00+07:00',
  },
  {
    id: 'P002',
    type: 'E',
    severity: 7,
    queuedAt: '2026-03-19T10:55:00+07:00',
  },
  {
    id: 'P003',
    type: 'N',
    severity: 8,
    queuedAt: '2026-03-19T09:50:00+07:00',
  },
];

console.log(getUrgentPatient(queue, currentTime));
// P003: it has waited at least 60 minutes, so it joins the Emergency
// priority class. Its severity 8 is then higher than P002's severity 7.
