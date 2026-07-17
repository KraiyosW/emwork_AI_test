CREATE TABLE patients (
  id BIGINT PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE TABLE staff (
  id BIGINT PRIMARY KEY,
  name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('doctor', 'pharmacist', 'nurse', 'admin')),
  can_override_allergy BOOLEAN NOT NULL DEFAULT FALSE,
  can_verify_allergy_override BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE drugs (
  id BIGINT PRIMARY KEY,
  generic_name TEXT NOT NULL UNIQUE
);

CREATE TABLE drug_allergies (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  patient_id BIGINT NOT NULL REFERENCES patients (id),
  drug_id BIGINT NOT NULL REFERENCES drugs (id),
  reaction TEXT,
  severity TEXT NOT NULL CHECK (
    severity IN ('mild', 'moderate', 'severe', 'life_threatening')
  ),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (patient_id, drug_id)
);

CREATE TABLE prescriptions (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  patient_id BIGINT NOT NULL REFERENCES patients (id),
  prescribed_by BIGINT NOT NULL REFERENCES staff (id),
  status TEXT NOT NULL DEFAULT 'draft' CHECK (
    status IN ('draft', 'pending_review', 'approved', 'cancelled')
  ),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  approved_at TIMESTAMPTZ
);

CREATE TABLE prescription_items (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  prescription_id BIGINT NOT NULL REFERENCES prescriptions (id) ON DELETE CASCADE,
  drug_id BIGINT NOT NULL REFERENCES drugs (id),
  dosage TEXT NOT NULL,
  frequency TEXT NOT NULL,
  UNIQUE (prescription_id, drug_id)
);

CREATE TABLE allergy_overrides (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  prescription_item_id BIGINT NOT NULL UNIQUE
    REFERENCES prescription_items (id) ON DELETE RESTRICT,
  overridden_by BIGINT NOT NULL REFERENCES staff (id),
  verified_by BIGINT REFERENCES staff (id),
  reason TEXT NOT NULL CHECK (CHAR_LENGTH(TRIM(reason)) >= 10),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION enforce_allergy_override_roles()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  override_role TEXT;
  override_allowed BOOLEAN;
  verifier_role TEXT;
  verifier_allowed BOOLEAN;
BEGIN
  SELECT role, can_override_allergy
  INTO override_role, override_allowed
  FROM staff
  WHERE id = NEW.overridden_by;

  IF override_role IS DISTINCT FROM 'doctor'
    OR NOT COALESCE(override_allowed, FALSE)
  THEN
    RAISE EXCEPTION 'Only an authorized doctor can override an allergy alert';
  END IF;

  IF NEW.verified_by IS NOT NULL THEN
    SELECT role, can_verify_allergy_override
    INTO verifier_role, verifier_allowed
    FROM staff
    WHERE id = NEW.verified_by;

    IF verifier_role IS DISTINCT FROM 'pharmacist'
      OR NOT COALESCE(verifier_allowed, FALSE)
    THEN
      RAISE EXCEPTION 'Verifier must be an authorized pharmacist';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enforce_allergy_override_roles
BEFORE INSERT OR UPDATE ON allergy_overrides
FOR EACH ROW
EXECUTE FUNCTION enforce_allergy_override_roles();

CREATE OR REPLACE FUNCTION validate_prescription_allergies()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status <> 'approved' THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM prescription_items
    WHERE prescription_id = NEW.id
  ) THEN
    RAISE EXCEPTION 'Cannot approve a prescription without items';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM prescription_items AS pi
    JOIN drug_allergies AS da
      ON da.patient_id = NEW.patient_id
     AND da.drug_id = pi.drug_id
     AND da.is_active = TRUE
    LEFT JOIN allergy_overrides AS ao
      ON ao.prescription_item_id = pi.id
    WHERE pi.prescription_id = NEW.id
      AND ao.id IS NULL
  ) THEN
    RAISE EXCEPTION 'ALLERGY_BLOCK: an allergy override is required';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM prescription_items AS pi
    JOIN drug_allergies AS da
      ON da.patient_id = NEW.patient_id
     AND da.drug_id = pi.drug_id
     AND da.is_active = TRUE
    JOIN allergy_overrides AS ao
      ON ao.prescription_item_id = pi.id
    WHERE pi.prescription_id = NEW.id
      AND da.severity IN ('severe', 'life_threatening')
      AND ao.verified_by IS NULL
  ) THEN
    RAISE EXCEPTION
      'ALLERGY_BLOCK: severe allergies require pharmacist verification';
  END IF;

  NEW.approved_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_prescription_allergies
BEFORE INSERT OR UPDATE ON prescriptions
FOR EACH ROW
EXECUTE FUNCTION validate_prescription_allergies();

CREATE INDEX idx_drug_allergies_active_patient_drug
  ON drug_allergies (patient_id, drug_id)
  WHERE is_active = TRUE;

CREATE INDEX idx_prescription_items_prescription_drug
  ON prescription_items (prescription_id, drug_id);
