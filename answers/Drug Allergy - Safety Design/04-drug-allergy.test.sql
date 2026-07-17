\set ON_ERROR_STOP on

BEGIN;

\ir 04-drug-allergy-schema.sql

INSERT INTO patients (id, name) VALUES
  (1, 'Patient A');

INSERT INTO staff (
  id,
  name,
  role,
  can_override_allergy,
  can_verify_allergy_override
) VALUES
  (1, 'Authorized Doctor', 'doctor', TRUE, FALSE),
  (2, 'Unauthorized Doctor', 'doctor', FALSE, FALSE),
  (3, 'Authorized Pharmacist', 'pharmacist', FALSE, TRUE);

INSERT INTO drugs (id, generic_name) VALUES
  (1, 'Safe Drug'),
  (2, 'Mild Allergy Drug'),
  (3, 'Severe Allergy Drug');

INSERT INTO drug_allergies (
  patient_id,
  drug_id,
  reaction,
  severity
) VALUES
  (1, 2, 'rash', 'mild'),
  (1, 3, 'anaphylaxis', 'severe');

DO $$
DECLARE
  safe_prescription_id BIGINT;
BEGIN
  INSERT INTO prescriptions (patient_id, prescribed_by)
  VALUES (1, 1)
  RETURNING id INTO safe_prescription_id;

  INSERT INTO prescription_items (
    prescription_id,
    drug_id,
    dosage,
    frequency
  ) VALUES
    (safe_prescription_id, 1, '500 mg', 'twice daily');

  UPDATE prescriptions
  SET status = 'approved'
  WHERE id = safe_prescription_id;
END;
$$;

DO $$
DECLARE
  blocked_prescription_id BIGINT;
BEGIN
  INSERT INTO prescriptions (patient_id, prescribed_by)
  VALUES (1, 1)
  RETURNING id INTO blocked_prescription_id;

  INSERT INTO prescription_items (
    prescription_id,
    drug_id,
    dosage,
    frequency
  ) VALUES
    (blocked_prescription_id, 2, '10 mg', 'once daily');

  BEGIN
    UPDATE prescriptions
    SET status = 'approved'
    WHERE id = blocked_prescription_id;

    RAISE EXCEPTION 'Expected allergy approval to be blocked';
  EXCEPTION
    WHEN RAISE_EXCEPTION THEN
      IF SQLERRM NOT LIKE 'ALLERGY_BLOCK:%' THEN
        RAISE;
      END IF;
  END;
END;
$$;

DO $$
DECLARE
  mild_prescription_id BIGINT;
  mild_item_id BIGINT;
BEGIN
  INSERT INTO prescriptions (patient_id, prescribed_by)
  VALUES (1, 1)
  RETURNING id INTO mild_prescription_id;

  INSERT INTO prescription_items (
    prescription_id,
    drug_id,
    dosage,
    frequency
  ) VALUES
    (mild_prescription_id, 2, '10 mg', 'once daily')
  RETURNING id INTO mild_item_id;

  INSERT INTO allergy_overrides (
    prescription_item_id,
    overridden_by,
    reason
  ) VALUES
    (mild_item_id, 1, 'Benefit outweighs the documented mild reaction');

  UPDATE prescriptions
  SET status = 'approved'
  WHERE id = mild_prescription_id;
END;
$$;

DO $$
DECLARE
  severe_prescription_id BIGINT;
  severe_item_id BIGINT;
BEGIN
  INSERT INTO prescriptions (patient_id, prescribed_by)
  VALUES (1, 1)
  RETURNING id INTO severe_prescription_id;

  INSERT INTO prescription_items (
    prescription_id,
    drug_id,
    dosage,
    frequency
  ) VALUES
    (severe_prescription_id, 3, '10 mg', 'once daily')
  RETURNING id INTO severe_item_id;

  INSERT INTO allergy_overrides (
    prescription_item_id,
    overridden_by,
    reason
  ) VALUES
    (severe_item_id, 1, 'Emergency treatment requires this medication');

  BEGIN
    UPDATE prescriptions
    SET status = 'approved'
    WHERE id = severe_prescription_id;

    RAISE EXCEPTION 'Expected pharmacist verification to be required';
  EXCEPTION
    WHEN RAISE_EXCEPTION THEN
      IF SQLERRM NOT LIKE 'ALLERGY_BLOCK:%' THEN
        RAISE;
      END IF;
  END;

  UPDATE allergy_overrides
  SET verified_by = 3
  WHERE prescription_item_id = severe_item_id;

  UPDATE prescriptions
  SET status = 'approved'
  WHERE id = severe_prescription_id;
END;
$$;

DO $$
DECLARE
  item_id BIGINT;
BEGIN
  SELECT pi.id
  INTO item_id
  FROM prescription_items AS pi
  JOIN prescriptions AS p ON p.id = pi.prescription_id
  WHERE p.patient_id = 1
    AND pi.drug_id = 2
    AND p.status = 'draft'
  LIMIT 1;

  BEGIN
    INSERT INTO allergy_overrides (
      prescription_item_id,
      overridden_by,
      reason
    ) VALUES
      (item_id, 2, 'Unauthorized override should not be accepted');

    RAISE EXCEPTION 'Expected unauthorized override to be blocked';
  EXCEPTION
    WHEN RAISE_EXCEPTION THEN
      IF SQLERRM NOT LIKE 'Only an authorized doctor%' THEN
        RAISE;
      END IF;
  END;
END;
$$;

\echo 'PASS: all drug allergy safety cases behaved as expected'

ROLLBACK;
