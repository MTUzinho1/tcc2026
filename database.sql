BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'user_role'
  ) THEN
    CREATE TYPE user_role AS ENUM (
      'admin',
      'librarian'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'copy_status'
  ) THEN
    CREATE TYPE copy_status AS ENUM (
      'available',
      'loaned',
      'damaged',
      'lost',
      'maintenance'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'loan_status'
  ) THEN
    CREATE TYPE loan_status AS ENUM (
      'active',
      'returned',
      'damaged',
      'lost'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'return_condition'
  ) THEN
    CREATE TYPE return_condition AS ENUM (
      'normal',
      'damaged',
      'lost'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'reservation_status'
  ) THEN
    CREATE TYPE reservation_status AS ENUM (
      'active',
      'ready',
      'completed',
      'cancelled',
      'expired'
    );
  END IF;
END
$$;



CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(120) NOT NULL,
  email VARCHAR(180) NOT NULL,
  password_hash TEXT NOT NULL,
  role user_role NOT NULL DEFAULT 'librarian',
  active BOOLEAN NOT NULL DEFAULT TRUE,
  last_login_at TIMESTAMPTZ,
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT users_email_lowercase
    CHECK (email = LOWER(email))
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS users_email_unique
  ON users (LOWER(email));

CREATE UNIQUE INDEX IF NOT EXISTS users_email_plain_unique
  ON users (email);

CREATE INDEX IF NOT EXISTS users_role_idx
  ON users (role);

CREATE INDEX IF NOT EXISTS users_active_idx
  ON users (active);

CREATE TABLE IF NOT EXISTS classes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(60) NOT NULL,
  shift VARCHAR(30) NOT NULL,
  school_year INTEGER NOT NULL,
  teacher_name VARCHAR(120),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT classes_school_year_check
    CHECK (school_year BETWEEN 2020 AND 2100),

  CONSTRAINT classes_shift_check
    CHECK (shift IN ('Manhã', 'Tarde', 'Noite', 'Integral')),

  CONSTRAINT classes_unique
    UNIQUE (name, shift, school_year)
);

CREATE INDEX IF NOT EXISTS classes_active_idx
  ON classes (active);

CREATE INDEX IF NOT EXISTS classes_school_year_idx
  ON classes (school_year DESC);

CREATE TABLE IF NOT EXISTS students (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name VARCHAR(160) NOT NULL,
  registration_number VARCHAR(40) NOT NULL UNIQUE,
  class_id UUID NOT NULL,
  roll_number INTEGER,
  guardian_contact VARCHAR(80),
  photo_url TEXT,
  notes TEXT,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT students_class_id_fk
    FOREIGN KEY (class_id)
    REFERENCES classes (id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,

  CONSTRAINT students_roll_number_check
    CHECK (
      roll_number IS NULL
      OR roll_number BETWEEN 1 AND 99
    )
);

ALTER TABLE students ADD COLUMN IF NOT EXISTS photo_url TEXT;

CREATE INDEX IF NOT EXISTS students_class_id_idx
  ON students (class_id);

CREATE INDEX IF NOT EXISTS students_active_idx
  ON students (active);

CREATE INDEX IF NOT EXISTS students_full_name_idx
  ON students (LOWER(full_name));

CREATE INDEX IF NOT EXISTS students_registration_number_idx
  ON students (registration_number);

CREATE TABLE IF NOT EXISTS categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(90) NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS categories_active_idx
  ON categories (active);

CREATE TABLE IF NOT EXISTS books (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title VARCHAR(180) NOT NULL,
  author VARCHAR(160) NOT NULL,
  isbn VARCHAR(30),
  publisher VARCHAR(120),
  publication_year INTEGER,
  category_id UUID,
  shelf VARCHAR(80),
  description TEXT,
  cover_url TEXT,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT books_category_id_fk
    FOREIGN KEY (category_id)
    REFERENCES categories (id)
    ON UPDATE CASCADE
    ON DELETE SET NULL,

  CONSTRAINT books_year_check
    CHECK (
      publication_year IS NULL
      OR publication_year BETWEEN 1000 AND 2100
    ),

  CONSTRAINT books_isbn_unique
    UNIQUE (isbn)
);

CREATE INDEX IF NOT EXISTS books_title_idx
  ON books (LOWER(title));

CREATE INDEX IF NOT EXISTS books_author_idx
  ON books (LOWER(author));

CREATE INDEX IF NOT EXISTS books_category_id_idx
  ON books (category_id);

CREATE INDEX IF NOT EXISTS books_active_idx
  ON books (active);

CREATE TABLE IF NOT EXISTS book_copies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id UUID NOT NULL,
  inventory_code VARCHAR(40) NOT NULL UNIQUE,
  status copy_status NOT NULL DEFAULT 'available',
  condition_notes TEXT,
  acquired_at DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT book_copies_book_id_fk
    FOREIGN KEY (book_id)
    REFERENCES books (id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS book_copies_book_id_idx
  ON book_copies (book_id);

CREATE INDEX IF NOT EXISTS book_copies_status_idx
  ON book_copies (status);

CREATE INDEX IF NOT EXISTS book_copies_inventory_code_idx
  ON book_copies (inventory_code);

CREATE TABLE IF NOT EXISTS loans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL,
  copy_id UUID NOT NULL,
  created_by UUID NOT NULL,
  loan_date DATE NOT NULL DEFAULT CURRENT_DATE,
  due_date DATE NOT NULL,
  returned_at TIMESTAMPTZ,
  status loan_status NOT NULL DEFAULT 'active',
  renewal_count INTEGER NOT NULL DEFAULT 0,
  notes TEXT,
  return_condition return_condition,
  return_notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT loans_student_id_fk
    FOREIGN KEY (student_id)
    REFERENCES students (id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,

  CONSTRAINT loans_copy_id_fk
    FOREIGN KEY (copy_id)
    REFERENCES book_copies (id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,

  CONSTRAINT loans_created_by_fk
    FOREIGN KEY (created_by)
    REFERENCES users (id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,

  CONSTRAINT loans_due_date_check
    CHECK (due_date >= loan_date),

  CONSTRAINT loans_renewal_count_check
    CHECK (renewal_count >= 0)
);

CREATE INDEX IF NOT EXISTS loans_student_id_idx
  ON loans (student_id);

CREATE INDEX IF NOT EXISTS loans_copy_id_idx
  ON loans (copy_id);

CREATE INDEX IF NOT EXISTS loans_created_by_idx
  ON loans (created_by);

CREATE INDEX IF NOT EXISTS loans_status_idx
  ON loans (status);

CREATE INDEX IF NOT EXISTS loans_due_date_idx
  ON loans (due_date);

CREATE INDEX IF NOT EXISTS loans_loan_date_idx
  ON loans (loan_date DESC);

CREATE UNIQUE INDEX IF NOT EXISTS loans_one_active_per_copy_idx
  ON loans (copy_id)
  WHERE status = 'active';

CREATE TABLE IF NOT EXISTS reservations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL,
  book_id UUID NOT NULL,
  created_by UUID NOT NULL,
  status reservation_status NOT NULL DEFAULT 'active',
  notes TEXT,
  ready_at TIMESTAMPTZ,
  expires_at DATE,
  completed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT reservations_student_id_fk
    FOREIGN KEY (student_id)
    REFERENCES students (id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,

  CONSTRAINT reservations_book_id_fk
    FOREIGN KEY (book_id)
    REFERENCES books (id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,

  CONSTRAINT reservations_created_by_fk
    FOREIGN KEY (created_by)
    REFERENCES users (id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS reservations_student_id_idx
  ON reservations (student_id);

CREATE INDEX IF NOT EXISTS reservations_book_id_idx
  ON reservations (book_id);

CREATE INDEX IF NOT EXISTS reservations_status_idx
  ON reservations (status);

CREATE INDEX IF NOT EXISTS reservations_created_at_idx
  ON reservations (created_at);

CREATE UNIQUE INDEX IF NOT EXISTS reservations_one_active_student_book_idx
  ON reservations (student_id, book_id)
  WHERE status IN ('active', 'ready');

CREATE TABLE IF NOT EXISTS notices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  loan_id UUID NOT NULL,
  created_by UUID NOT NULL,
  channel VARCHAR(80) NOT NULL,
  result VARCHAR(100) NOT NULL DEFAULT 'Avisado',
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT notices_loan_id_fk
    FOREIGN KEY (loan_id)
    REFERENCES loans (id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,

  CONSTRAINT notices_created_by_fk
    FOREIGN KEY (created_by)
    REFERENCES users (id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
);

ALTER TABLE notices
  ADD COLUMN IF NOT EXISTS result VARCHAR(100) NOT NULL DEFAULT 'Avisado';

CREATE INDEX IF NOT EXISTS notices_loan_id_idx
  ON notices (loan_id);

CREATE INDEX IF NOT EXISTS notices_created_at_idx
  ON notices (created_at DESC);

CREATE TABLE IF NOT EXISTS settings (
  id SMALLINT PRIMARY KEY DEFAULT 1,
  school_name VARCHAR(120) NOT NULL DEFAULT 'Minha Escola',
  library_name VARCHAR(120) NOT NULL DEFAULT 'Biblioteca Escolar',
  contact_email VARCHAR(180),
  contact_phone VARCHAR(40),
  current_school_year INTEGER NOT NULL DEFAULT 2026,
  default_loan_days INTEGER NOT NULL DEFAULT 14,
  max_active_loans INTEGER NOT NULL DEFAULT 2,
  max_renewals INTEGER NOT NULL DEFAULT 1,
  renewal_days INTEGER NOT NULL DEFAULT 7,
  due_soon_days INTEGER NOT NULL DEFAULT 2,
  reservation_hold_days INTEGER NOT NULL DEFAULT 3,
  block_overdue_students BOOLEAN NOT NULL DEFAULT TRUE,
  notice_template TEXT NOT NULL DEFAULT 'Olá, informamos que o aluno {aluno}, da turma {turma}, está com o livro “{livro}” em atraso desde {data}. O atraso é de {dias} dia(s). Pedimos a devolução à biblioteca da {escola}.',
  reservation_template TEXT NOT NULL DEFAULT 'Olá, {aluno}. O livro “{livro}” reservado para você está disponível na biblioteca da {escola} até {validade}.',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT settings_single_row
    CHECK (id = 1),

  CONSTRAINT settings_current_school_year_check
    CHECK (current_school_year BETWEEN 2020 AND 2100),

  CONSTRAINT settings_default_loan_days_check
    CHECK (default_loan_days BETWEEN 1 AND 90),

  CONSTRAINT settings_max_active_loans_check
    CHECK (max_active_loans BETWEEN 1 AND 20),

  CONSTRAINT settings_max_renewals_check
    CHECK (max_renewals BETWEEN 0 AND 10),

  CONSTRAINT settings_renewal_days_check
    CHECK (renewal_days BETWEEN 1 AND 90),

  CONSTRAINT settings_due_soon_days_check
    CHECK (due_soon_days BETWEEN 0 AND 30),

  CONSTRAINT settings_reservation_hold_days_check
    CHECK (reservation_hold_days BETWEEN 1 AND 30)
);

ALTER TABLE settings
  ADD COLUMN IF NOT EXISTS library_name VARCHAR(120) NOT NULL DEFAULT 'Biblioteca Escolar';

ALTER TABLE settings
  ADD COLUMN IF NOT EXISTS contact_email VARCHAR(180);

ALTER TABLE settings
  ADD COLUMN IF NOT EXISTS contact_phone VARCHAR(40);

ALTER TABLE settings
  ADD COLUMN IF NOT EXISTS current_school_year INTEGER NOT NULL DEFAULT 2026;

ALTER TABLE settings
  ADD COLUMN IF NOT EXISTS reservation_hold_days INTEGER NOT NULL DEFAULT 3;

ALTER TABLE settings
  ADD COLUMN IF NOT EXISTS block_overdue_students BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE settings
  ADD COLUMN IF NOT EXISTS reservation_template TEXT NOT NULL DEFAULT 'Olá, {aluno}. O livro “{livro}” reservado para você está disponível na biblioteca da {escola} até {validade}.';

INSERT INTO settings (
  id,
  school_name,
  library_name,
  current_school_year,
  default_loan_days,
  max_active_loans,
  max_renewals,
  renewal_days,
  due_soon_days,
  reservation_hold_days,
  block_overdue_students
)
VALUES (
  1,
  'Minha Escola',
  'Biblioteca Escolar',
  2026,
  14,
  2,
  1,
  7,
  2,
  3,
  TRUE
)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS audit_logs (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID,
  action VARCHAR(80) NOT NULL,
  entity_type VARCHAR(80) NOT NULL,
  entity_id TEXT,
  details JSONB NOT NULL DEFAULT '{}'::JSONB,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT audit_logs_user_id_fk
    FOREIGN KEY (user_id)
    REFERENCES users (id)
    ON UPDATE CASCADE
    ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS audit_logs_user_id_idx
  ON audit_logs (user_id);

CREATE INDEX IF NOT EXISTS audit_logs_entity_idx
  ON audit_logs (entity_type, entity_id);

CREATE INDEX IF NOT EXISTS audit_logs_action_idx
  ON audit_logs (action);

CREATE INDEX IF NOT EXISTS audit_logs_created_at_idx
  ON audit_logs (created_at DESC);

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_set_updated_at
  ON users;

CREATE TRIGGER users_set_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS classes_set_updated_at
  ON classes;

CREATE TRIGGER classes_set_updated_at
BEFORE UPDATE ON classes
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS students_set_updated_at
  ON students;

CREATE TRIGGER students_set_updated_at
BEFORE UPDATE ON students
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS books_set_updated_at
  ON books;

CREATE TRIGGER books_set_updated_at
BEFORE UPDATE ON books
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS book_copies_set_updated_at
  ON book_copies;

CREATE TRIGGER book_copies_set_updated_at
BEFORE UPDATE ON book_copies
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS loans_set_updated_at
  ON loans;

CREATE TRIGGER loans_set_updated_at
BEFORE UPDATE ON loans
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS reservations_set_updated_at
  ON reservations;

CREATE TRIGGER reservations_set_updated_at
BEFORE UPDATE ON reservations
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS settings_set_updated_at
  ON settings;

CREATE TRIGGER settings_set_updated_at
BEFORE UPDATE ON settings
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE VIEW view_books_inventory AS
SELECT
  b.id,
  b.title,
  b.author,
  b.isbn,
  b.publisher,
  b.publication_year,
  b.category_id,
  c.name AS category_name,
  b.shelf,
  b.active,
  COUNT(bc.id)::INTEGER AS total_copies,
  COUNT(bc.id) FILTER (
    WHERE bc.status = 'available'
  )::INTEGER AS available_copies,
  COUNT(bc.id) FILTER (
    WHERE bc.status = 'loaned'
  )::INTEGER AS loaned_copies,
  COUNT(bc.id) FILTER (
    WHERE bc.status = 'damaged'
  )::INTEGER AS damaged_copies,
  COUNT(bc.id) FILTER (
    WHERE bc.status = 'lost'
  )::INTEGER AS lost_copies,
  COUNT(bc.id) FILTER (
    WHERE bc.status = 'maintenance'
  )::INTEGER AS maintenance_copies
FROM books b
LEFT JOIN categories c
  ON c.id = b.category_id
LEFT JOIN book_copies bc
  ON bc.book_id = b.id
GROUP BY
  b.id,
  c.id;

CREATE OR REPLACE VIEW view_active_loans AS
SELECT
  l.id,
  l.loan_date,
  l.due_date,
  l.renewal_count,
  s.id AS student_id,
  s.full_name AS student_name,
  s.registration_number,
  c.id AS class_id,
  c.name AS class_name,
  b.id AS book_id,
  b.title AS book_title,
  bc.id AS copy_id,
  bc.inventory_code,
  CASE
    WHEN l.due_date < CURRENT_DATE
      THEN 'overdue'
    ELSE 'active'
  END AS calculated_status,
  GREATEST(
    CURRENT_DATE - l.due_date,
    0
  )::INTEGER AS overdue_days
FROM loans l
JOIN students s
  ON s.id = l.student_id
LEFT JOIN classes c
  ON c.id = s.class_id
JOIN book_copies bc
  ON bc.id = l.copy_id
JOIN books b
  ON b.id = bc.book_id
WHERE l.status = 'active';

CREATE OR REPLACE VIEW view_student_library_status AS
SELECT
  s.id,
  s.full_name,
  s.registration_number,
  s.class_id,
  c.name AS class_name,
  s.active,
  COUNT(DISTINCT l.id) FILTER (
    WHERE l.status = 'active'
  )::INTEGER AS active_loans,
  COUNT(DISTINCT l.id) FILTER (
    WHERE l.status = 'active'
      AND l.due_date < CURRENT_DATE
  )::INTEGER AS overdue_loans,
  COUNT(DISTINCT l.id)::INTEGER AS total_loans,
  COUNT(DISTINCT r.id) FILTER (
    WHERE r.status IN ('active', 'ready')
  )::INTEGER AS active_reservations
FROM students s
LEFT JOIN classes c
  ON c.id = s.class_id
LEFT JOIN loans l
  ON l.student_id = s.id
LEFT JOIN reservations r
  ON r.student_id = s.id
GROUP BY
  s.id,
  c.id;

CREATE OR REPLACE VIEW view_pending_loans AS
SELECT
  l.id,
  l.student_id,
  l.copy_id,
  l.loan_date,
  l.due_date,
  s.full_name AS student_name,
  s.registration_number,
  s.guardian_contact,
  c.name AS class_name,
  b.id AS book_id,
  b.title AS book_title,
  bc.inventory_code,
  (CURRENT_DATE - l.due_date)::INTEGER AS overdue_days,
  COALESCE(notice_data.notice_count, 0)::INTEGER AS notice_count,
  notice_data.last_notice_at
FROM loans l
JOIN students s
  ON s.id = l.student_id
LEFT JOIN classes c
  ON c.id = s.class_id
JOIN book_copies bc
  ON bc.id = l.copy_id
JOIN books b
  ON b.id = bc.book_id
LEFT JOIN (
  SELECT
    loan_id,
    COUNT(*)::INTEGER AS notice_count,
    MAX(created_at) AS last_notice_at
  FROM notices
  GROUP BY loan_id
) notice_data
  ON notice_data.loan_id = l.id
WHERE l.status = 'active'
  AND l.due_date < CURRENT_DATE;

INSERT INTO categories (name)
VALUES
  ('Literatura Brasileira'),
  ('Literatura Estrangeira'),
  ('Infantojuvenil'),
  ('Poesia'),
  ('Contos e Crônicas'),
  ('Ciências'),
  ('Biologia'),
  ('Física'),
  ('Química'),
  ('Matemática'),
  ('História'),
  ('Geografia'),
  ('Filosofia'),
  ('Sociologia'),
  ('Artes'),
  ('Tecnologia'),
  ('Biografias'),
  ('Quadrinhos'),
  ('Vestibular e ENEM'),
  ('Dicionários e Referência')
ON CONFLICT (name) DO NOTHING;

-- Contas iniciais para apresentação.
-- Em uma instalação nova, cria as senhas abaixo.
-- Se a conta já existir, preserva a senha alterada pelo administrador.
INSERT INTO users (name, email, password_hash, password_changed_at, role, active) VALUES
  (
    'Administrador BookShare',
    'admin@bookshare.com',
    crypt('BookShare@2026', gen_salt('bf', 12)),
    NULL,
    'admin'::user_role,
    TRUE
  ),
  (
    'Bibliotecária',
    'biblioteca@bookshare.com',
    crypt('Biblioteca@2026', gen_salt('bf', 12)),
    NULL,
    'librarian'::user_role,
    TRUE
  )
ON CONFLICT (email) DO UPDATE SET
  name = EXCLUDED.name,
  role = EXCLUDED.role,
  active = TRUE,
  updated_at = NOW();

INSERT INTO classes (name, shift, school_year, teacher_name, active) VALUES
  ('3º A', 'Manhã', 2026, 'Professora Ana Martins', TRUE),
  ('3º B', 'Manhã', 2026, 'Professor Carlos Mendes', TRUE)
ON CONFLICT (name, shift, school_year) DO UPDATE SET
  teacher_name = EXCLUDED.teacher_name,
  active = TRUE,
  updated_at = NOW();

INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Ana Clara Souza', '2026A001', c.id, 1, '(41) 90001-0173', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Arthur Henrique Lima', '2026A002', c.id, 2, '(41) 90002-0346', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Beatriz Oliveira Santos', '2026A003', c.id, 3, '(41) 90003-0519', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Bruno Rafael Costa', '2026A004', c.id, 4, '(41) 90004-0692', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Camila Ferreira Alves', '2026A005', c.id, 5, '(41) 90005-0865', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Carlos Eduardo Ribeiro', '2026A006', c.id, 6, '(41) 90006-1038', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Daniela Martins Rocha', '2026A007', c.id, 7, '(41) 90007-1211', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Davi Lucas Gomes', '2026A008', c.id, 8, '(41) 90008-1384', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Eduarda Vitória Silva', '2026A009', c.id, 9, '(41) 90009-1557', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Enzo Gabriel Pereira', '2026A010', c.id, 10, '(41) 90010-1730', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Fernanda Almeida Castro', '2026A011', c.id, 11, '(41) 90011-1903', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Felipe Augusto Nunes', '2026A012', c.id, 12, '(41) 90012-2076', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Gabriela Rodrigues Melo', '2026A013', c.id, 13, '(41) 90013-2249', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Gustavo Henrique Barros', '2026A014', c.id, 14, '(41) 90014-2422', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Helena Cristina Moraes', '2026A015', c.id, 15, '(41) 90015-2595', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Igor Matheus Cardoso', '2026A016', c.id, 16, '(41) 90016-2768', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Isabela Fernandes Dias', '2026A017', c.id, 17, '(41) 90017-2941', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'João Pedro Batista', '2026A018', c.id, 18, '(41) 90018-3114', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Júlia Caroline Vieira', '2026A019', c.id, 19, '(41) 90019-3287', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Kaique Vinícius Ramos', '2026A020', c.id, 20, '(41) 90020-3460', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Larissa Monteiro Freitas', '2026A021', c.id, 21, '(41) 90021-3633', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Leonardo Gabriel Pinto', '2026A022', c.id, 22, '(41) 90022-3806', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Letícia Aparecida Lopes', '2026A023', c.id, 23, '(41) 90023-3979', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Lucas Rafael Teixeira', '2026A024', c.id, 24, '(41) 90024-4152', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Luana Beatriz Andrade', '2026A025', c.id, 25, '(41) 90025-4325', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Marcos Vinícius Moreira', '2026A026', c.id, 26, '(41) 90026-4498', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Maria Eduarda Campos', '2026A027', c.id, 27, '(41) 90027-4671', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Matheus Felipe Barbosa', '2026A028', c.id, 28, '(41) 90028-4844', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Nathalia Cristina Martins', '2026A029', c.id, 29, '(41) 90029-5017', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Pedro Henrique Araújo', '2026A030', c.id, 30, '(41) 90030-5190', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º A' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Alice Vitória Carvalho', '2026B001', c.id, 1, '(41) 90001-0173', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'André Luiz Correia', '2026B002', c.id, 2, '(41) 90002-0346', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Bianca Gabrielly Farias', '2026B003', c.id, 3, '(41) 90003-0519', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Caio Henrique Mendes', '2026B004', c.id, 4, '(41) 90004-0692', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Carolina Alves Cunha', '2026B005', c.id, 5, '(41) 90005-0865', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Cauã Felipe Miranda', '2026B006', c.id, 6, '(41) 90006-1038', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Débora Cristina Lima', '2026B007', c.id, 7, '(41) 90007-1211', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Diego Rafael Souza', '2026B008', c.id, 8, '(41) 90008-1384', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Emanuelly Vitória Rocha', '2026B009', c.id, 9, '(41) 90009-1557', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Eric Gabriel Martins', '2026B010', c.id, 10, '(41) 90010-1730', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Ester Caroline Santos', '2026B011', c.id, 11, '(41) 90011-1903', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Flávia Beatriz Prado', '2026B012', c.id, 12, '(41) 90012-2076', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Gabriel Henrique Reis', '2026B013', c.id, 13, '(41) 90013-2249', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Giovana Cristina Neves', '2026B014', c.id, 14, '(41) 90014-2422', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Heitor Augusto Silva', '2026B015', c.id, 15, '(41) 90015-2595', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Heloísa Fernandes Costa', '2026B016', c.id, 16, '(41) 90016-2768', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'José Victor Almeida', '2026B017', c.id, 17, '(41) 90017-2941', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Karen Luiza Nascimento', '2026B018', c.id, 18, '(41) 90018-3114', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Laura Beatriz Gomes', '2026B019', c.id, 19, '(41) 90019-3287', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Leandro Matheus Dias', '2026B020', c.id, 20, '(41) 90020-3460', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Lívia Caroline Ribeiro', '2026B021', c.id, 21, '(41) 90021-3633', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Lorena Vitória Pinto', '2026B022', c.id, 22, '(41) 90022-3806', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Luiz Gustavo Ferreira', '2026B023', c.id, 23, '(41) 90023-3979', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Manuela Cristina Barros', '2026B024', c.id, 24, '(41) 90024-4152', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Miguel Henrique Lopes', '2026B025', c.id, 25, '(41) 90025-4325', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Nicole Gabriela Castro', '2026B026', c.id, 26, '(41) 90026-4498', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Rafael Augusto Moraes', '2026B027', c.id, 27, '(41) 90027-4671', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Samuel Lucas Oliveira', '2026B028', c.id, 28, '(41) 90028-4844', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Sophia Vitória Pereira', '2026B029', c.id, 29, '(41) 90029-5017', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();
INSERT INTO students (full_name, registration_number, class_id, roll_number, guardian_contact, notes, active)
SELECT 'Vitor Hugo Rodrigues', '2026B030', c.id, 30, '(41) 90030-5190', 'Aluno de demonstração', TRUE
FROM classes c WHERE c.name = '3º B' AND c.shift = 'Manhã' AND c.school_year = 2026
ON CONFLICT (registration_number) DO UPDATE SET
  full_name = EXCLUDED.full_name, class_id = EXCLUDED.class_id, roll_number = EXCLUDED.roll_number, guardian_contact = EXCLUDED.guardian_contact, active = TRUE, updated_at = NOW();

-- Fotografias de demonstração dos alunos. Substitua pelas fotos autorizadas da escola no painel.



-- Fotografias demonstrativas reais para os 60 alunos.
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/3.jpg' WHERE registration_number = '2026A001';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/10.jpg' WHERE registration_number = '2026A002';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/17.jpg' WHERE registration_number = '2026A003';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/24.jpg' WHERE registration_number = '2026A004';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/31.jpg' WHERE registration_number = '2026A005';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/38.jpg' WHERE registration_number = '2026A006';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/45.jpg' WHERE registration_number = '2026A007';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/52.jpg' WHERE registration_number = '2026A008';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/59.jpg' WHERE registration_number = '2026A009';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/66.jpg' WHERE registration_number = '2026A010';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/73.jpg' WHERE registration_number = '2026A011';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/80.jpg' WHERE registration_number = '2026A012';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/87.jpg' WHERE registration_number = '2026A013';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/94.jpg' WHERE registration_number = '2026A014';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/1.jpg' WHERE registration_number = '2026A015';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/8.jpg' WHERE registration_number = '2026A016';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/15.jpg' WHERE registration_number = '2026A017';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/22.jpg' WHERE registration_number = '2026A018';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/29.jpg' WHERE registration_number = '2026A019';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/36.jpg' WHERE registration_number = '2026A020';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/43.jpg' WHERE registration_number = '2026A021';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/50.jpg' WHERE registration_number = '2026A022';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/57.jpg' WHERE registration_number = '2026A023';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/64.jpg' WHERE registration_number = '2026A024';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/71.jpg' WHERE registration_number = '2026A025';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/78.jpg' WHERE registration_number = '2026A026';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/85.jpg' WHERE registration_number = '2026A027';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/92.jpg' WHERE registration_number = '2026A028';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/99.jpg' WHERE registration_number = '2026A029';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/6.jpg' WHERE registration_number = '2026A030';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/13.jpg' WHERE registration_number = '2026B001';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/20.jpg' WHERE registration_number = '2026B002';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/27.jpg' WHERE registration_number = '2026B003';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/34.jpg' WHERE registration_number = '2026B004';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/41.jpg' WHERE registration_number = '2026B005';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/48.jpg' WHERE registration_number = '2026B006';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/55.jpg' WHERE registration_number = '2026B007';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/62.jpg' WHERE registration_number = '2026B008';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/69.jpg' WHERE registration_number = '2026B009';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/76.jpg' WHERE registration_number = '2026B010';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/83.jpg' WHERE registration_number = '2026B011';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/90.jpg' WHERE registration_number = '2026B012';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/97.jpg' WHERE registration_number = '2026B013';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/4.jpg' WHERE registration_number = '2026B014';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/11.jpg' WHERE registration_number = '2026B015';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/18.jpg' WHERE registration_number = '2026B016';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/25.jpg' WHERE registration_number = '2026B017';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/32.jpg' WHERE registration_number = '2026B018';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/39.jpg' WHERE registration_number = '2026B019';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/46.jpg' WHERE registration_number = '2026B020';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/53.jpg' WHERE registration_number = '2026B021';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/60.jpg' WHERE registration_number = '2026B022';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/67.jpg' WHERE registration_number = '2026B023';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/74.jpg' WHERE registration_number = '2026B024';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/81.jpg' WHERE registration_number = '2026B025';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/88.jpg' WHERE registration_number = '2026B026';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/95.jpg' WHERE registration_number = '2026B027';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/2.jpg' WHERE registration_number = '2026B028';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/women/9.jpg' WHERE registration_number = '2026B029';
UPDATE students SET photo_url = 'https://randomuser.me/api/portraits/men/16.jpg' WHERE registration_number = '2026B030';

INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Dom Casmurro', 'Machado de Assis', 'BOOKSHARE-001', 'Acervo BookShare', 1899, c.id, 'A-01', 'Exemplar de demonstração da categoria Literatura Brasileira. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23164c43%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d4ae62%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ELITERATURA%20BRASILEIRA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%92%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EDom%20Casmurro%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EMachado%20de%20Assis%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Literatura Brasileira'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-001-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-001'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-001-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-001'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Memórias Póstumas de Brás Cubas', 'Machado de Assis', 'BOOKSHARE-002', 'Acervo BookShare', 1881, c.id, 'A-02', 'Exemplar de demonstração da categoria Literatura Brasileira. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23164c43%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d4ae62%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ELITERATURA%20BRASILEIRA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%92%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EMem%C3%B3rias%20P%C3%B3stumas%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3Ede%20Br%C3%A1s%20Cubas%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EMachado%20de%20Assis%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Literatura Brasileira'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-002-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-002'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-002-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-002'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'O Cortiço', 'Aluísio Azevedo', 'BOOKSHARE-003', 'Acervo BookShare', 1890, c.id, 'A-03', 'Exemplar de demonstração da categoria Literatura Brasileira. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23164c43%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d4ae62%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ELITERATURA%20BRASILEIRA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%92%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EO%20Corti%C3%A7o%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EAlu%C3%ADsio%20Azevedo%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Literatura Brasileira'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-003-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-003'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-003-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-003'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Vidas Secas', 'Graciliano Ramos', 'BOOKSHARE-004', 'Acervo BookShare', 1938, c.id, 'A-04', 'Exemplar de demonstração da categoria Literatura Brasileira. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23164c43%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d4ae62%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ELITERATURA%20BRASILEIRA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%92%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EVidas%20Secas%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EGraciliano%20Ramos%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Literatura Brasileira'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-004-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-004'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-004-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-004'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Capitães da Areia', 'Jorge Amado', 'BOOKSHARE-005', 'Acervo BookShare', 1937, c.id, 'A-05', 'Exemplar de demonstração da categoria Literatura Brasileira. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23164c43%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d4ae62%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ELITERATURA%20BRASILEIRA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%92%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3ECapit%C3%A3es%20da%20Areia%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EJorge%20Amado%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Literatura Brasileira'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-005-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-005'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-005-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-005'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Crime e Castigo', 'Fiódor Dostoiévski', 'BOOKSHARE-006', 'Acervo BookShare', 1866, c.id, 'A-06', 'Exemplar de demonstração da categoria Literatura Estrangeira. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%237a2d32%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d9a56c%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ELITERATURA%20ESTRANGEIRA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%98%85%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3ECrime%20e%20Castigo%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EFi%C3%B3dor%20Dostoi%C3%A9vski%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Literatura Estrangeira'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-006-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-006'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-006-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-006'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Os Irmãos Karamázov', 'Fiódor Dostoiévski', 'BOOKSHARE-007', 'Acervo BookShare', 1880, c.id, 'A-07', 'Exemplar de demonstração da categoria Literatura Estrangeira. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%237a2d32%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d9a56c%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ELITERATURA%20ESTRANGEIRA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%98%85%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EOs%20Irm%C3%A3os%20Karam%C3%A1zov%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EFi%C3%B3dor%20Dostoi%C3%A9vski%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Literatura Estrangeira'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-007-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-007'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-007-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-007'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Guerra e Paz', 'Liev Tolstói', 'BOOKSHARE-008', 'Acervo BookShare', 1869, c.id, 'A-08', 'Exemplar de demonstração da categoria Literatura Estrangeira. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%237a2d32%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d9a56c%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ELITERATURA%20ESTRANGEIRA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%98%85%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EGuerra%20e%20Paz%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ELiev%20Tolst%C3%B3i%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Literatura Estrangeira'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-008-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-008'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-008-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-008'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Anna Kariênina', 'Liev Tolstói', 'BOOKSHARE-009', 'Acervo BookShare', 1878, c.id, 'A-09', 'Exemplar de demonstração da categoria Literatura Estrangeira. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%237a2d32%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d9a56c%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ELITERATURA%20ESTRANGEIRA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%98%85%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EAnna%20Kari%C3%AAnina%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ELiev%20Tolst%C3%B3i%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Literatura Estrangeira'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-009-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-009'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-009-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-009'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'O Mestre e Margarida', 'Mikhail Bulgákov', 'BOOKSHARE-010', 'Acervo BookShare', 1967, c.id, 'A-10', 'Exemplar de demonstração da categoria Literatura Estrangeira. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%237a2d32%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d9a56c%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ELITERATURA%20ESTRANGEIRA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%98%85%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EO%20Mestre%20e%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EMargarida%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EMikhail%20Bulg%C3%A1kov%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Literatura Estrangeira'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-010-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-010'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-010-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-010'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'O Pequeno Príncipe', 'Antoine de Saint-Exupéry', 'BOOKSHARE-011', 'Acervo BookShare', 1943, c.id, 'A-11', 'Exemplar de demonstração da categoria Infantojuvenil. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%232c6e9e%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23f2cc68%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EINFANTOJUVENIL%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%A6%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EO%20Pequeno%20Pr%C3%ADncipe%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EAntoine%20de%20Saint-Exup%C3%A9ry%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Infantojuvenil'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-011-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-011'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-011-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-011'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Alice no País das Maravilhas', 'Lewis Carroll', 'BOOKSHARE-012', 'Acervo BookShare', 1865, c.id, 'A-12', 'Exemplar de demonstração da categoria Infantojuvenil. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%232c6e9e%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23f2cc68%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EINFANTOJUVENIL%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%A6%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EAlice%20no%20Pa%C3%ADs%20das%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EMaravilhas%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ELewis%20Carroll%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Infantojuvenil'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-012-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-012'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-012-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-012'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'As Aventuras de Tom Sawyer', 'Mark Twain', 'BOOKSHARE-013', 'Acervo BookShare', 1876, c.id, 'A-13', 'Exemplar de demonstração da categoria Infantojuvenil. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%232c6e9e%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23f2cc68%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EINFANTOJUVENIL%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%A6%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EAs%20Aventuras%20de%20Tom%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3ESawyer%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EMark%20Twain%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Infantojuvenil'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-013-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-013'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-013-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-013'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'O Mágico de Oz', 'L. Frank Baum', 'BOOKSHARE-014', 'Acervo BookShare', 1900, c.id, 'A-14', 'Exemplar de demonstração da categoria Infantojuvenil. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%232c6e9e%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23f2cc68%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EINFANTOJUVENIL%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%A6%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EO%20M%C3%A1gico%20de%20Oz%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EL.%20Frank%20Baum%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Infantojuvenil'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-014-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-014'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-014-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-014'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'A Ilha do Tesouro', 'Robert Louis Stevenson', 'BOOKSHARE-015', 'Acervo BookShare', 1883, c.id, 'A-15', 'Exemplar de demonstração da categoria Infantojuvenil. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%232c6e9e%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23f2cc68%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EINFANTOJUVENIL%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%A6%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EA%20Ilha%20do%20Tesouro%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ERobert%20Louis%20Stevenson%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Infantojuvenil'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-015-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-015'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-015-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-015'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Alguma Poesia', 'Carlos Drummond de Andrade', 'BOOKSHARE-016', 'Acervo BookShare', 1930, c.id, 'A-16', 'Exemplar de demonstração da categoria Poesia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%236e4c8b%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d9b4e7%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EPOESIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9D%A6%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EAlguma%20Poesia%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ECarlos%20Drummond%20de%20Andrade%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Poesia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-016-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-016'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-016-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-016'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Mensagem', 'Fernando Pessoa', 'BOOKSHARE-017', 'Acervo BookShare', 1934, c.id, 'A-17', 'Exemplar de demonstração da categoria Poesia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%236e4c8b%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d9b4e7%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EPOESIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9D%A6%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EMensagem%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EFernando%20Pessoa%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Poesia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-017-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-017'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-017-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-017'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Antologia Poética', 'Vinicius de Moraes', 'BOOKSHARE-018', 'Acervo BookShare', 1954, c.id, 'A-18', 'Exemplar de demonstração da categoria Poesia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%236e4c8b%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d9b4e7%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EPOESIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9D%A6%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EAntologia%20Po%C3%A9tica%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EVinicius%20de%20Moraes%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Poesia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-018-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-018'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-018-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-018'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Romanceiro da Inconfidência', 'Cecília Meireles', 'BOOKSHARE-019', 'Acervo BookShare', 1953, c.id, 'A-19', 'Exemplar de demonstração da categoria Poesia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%236e4c8b%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d9b4e7%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EPOESIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9D%A6%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3ERomanceiro%20da%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EInconfid%C3%AAncia%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ECec%C3%ADlia%20Meireles%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Poesia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-019-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-019'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-019-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-019'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Os Lusíadas', 'Luís de Camões', 'BOOKSHARE-020', 'Acervo BookShare', 1572, c.id, 'A-20', 'Exemplar de demonstração da categoria Poesia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%236e4c8b%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d9b4e7%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EPOESIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9D%A6%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EOs%20Lus%C3%ADadas%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ELu%C3%ADs%20de%20Cam%C3%B5es%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Poesia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-020-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-020'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-020-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-020'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Laços de Família', 'Clarice Lispector', 'BOOKSHARE-021', 'Acervo BookShare', 1960, c.id, 'B-01', 'Exemplar de demonstração da categoria Contos e Crônicas. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%237d5541%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23e3b68f%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ECONTOS%20E%20CR%C3%94NICAS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%98%95%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3ELa%C3%A7os%20de%20Fam%C3%ADlia%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EClarice%20Lispector%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Contos e Crônicas'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-021-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-021'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Morangos Mofados', 'Caio Fernando Abreu', 'BOOKSHARE-022', 'Acervo BookShare', 1982, c.id, 'B-02', 'Exemplar de demonstração da categoria Contos e Crônicas. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%237d5541%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23e3b68f%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ECONTOS%20E%20CR%C3%94NICAS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%98%95%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EMorangos%20Mofados%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ECaio%20Fernando%20Abreu%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Contos e Crônicas'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-022-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-022'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Contos Novos', 'Mário de Andrade', 'BOOKSHARE-023', 'Acervo BookShare', 1947, c.id, 'B-03', 'Exemplar de demonstração da categoria Contos e Crônicas. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%237d5541%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23e3b68f%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ECONTOS%20E%20CR%C3%94NICAS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%98%95%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EContos%20Novos%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EM%C3%A1rio%20de%20Andrade%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Contos e Crônicas'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-023-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-023'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Primeiras Estórias', 'João Guimarães Rosa', 'BOOKSHARE-024', 'Acervo BookShare', 1962, c.id, 'B-04', 'Exemplar de demonstração da categoria Contos e Crônicas. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%237d5541%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23e3b68f%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ECONTOS%20E%20CR%C3%94NICAS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%98%95%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EPrimeiras%20Est%C3%B3rias%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EJo%C3%A3o%20Guimar%C3%A3es%20Rosa%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Contos e Crônicas'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-024-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-024'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'O Alienista', 'Machado de Assis', 'BOOKSHARE-025', 'Acervo BookShare', 1882, c.id, 'B-05', 'Exemplar de demonstração da categoria Contos e Crônicas. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%237d5541%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23e3b68f%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ECONTOS%20E%20CR%C3%94NICAS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%98%95%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EO%20Alienista%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EMachado%20de%20Assis%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Contos e Crônicas'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-025-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-025'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Cosmos', 'Carl Sagan', 'BOOKSHARE-026', 'Acervo BookShare', 1980, c.id, 'B-06', 'Exemplar de demonstração da categoria Ciências. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23174c67%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2370c3cf%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ECI%C3%8ANCIAS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9A%9B%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3ECosmos%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ECarl%20Sagan%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Ciências'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-026-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-026'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-026-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-026'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'O Mundo Assombrado pelos Demônios', 'Carl Sagan', 'BOOKSHARE-027', 'Acervo BookShare', 1995, c.id, 'B-07', 'Exemplar de demonstração da categoria Ciências. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23174c67%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2370c3cf%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ECI%C3%8ANCIAS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9A%9B%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EO%20Mundo%20Assombrado%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3Epelos%20Dem%C3%B4nios%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ECarl%20Sagan%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Ciências'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-027-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-027'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'A Origem das Espécies', 'Charles Darwin', 'BOOKSHARE-028', 'Acervo BookShare', 1859, c.id, 'B-08', 'Exemplar de demonstração da categoria Ciências. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23174c67%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2370c3cf%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ECI%C3%8ANCIAS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9A%9B%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EA%20Origem%20das%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EEsp%C3%A9cies%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ECharles%20Darwin%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Ciências'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-028-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-028'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Primavera Silenciosa', 'Rachel Carson', 'BOOKSHARE-029', 'Acervo BookShare', 1962, c.id, 'B-09', 'Exemplar de demonstração da categoria Ciências. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23174c67%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2370c3cf%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ECI%C3%8ANCIAS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9A%9B%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EPrimavera%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3ESilenciosa%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ERachel%20Carson%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Ciências'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-029-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-029'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Breves Respostas para Grandes Questões', 'Stephen Hawking', 'BOOKSHARE-030', 'Acervo BookShare', 2018, c.id, 'B-10', 'Exemplar de demonstração da categoria Ciências. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23174c67%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2370c3cf%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ECI%C3%8ANCIAS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9A%9B%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EBreves%20Respostas%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3Epara%20Grandes%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EQuest%C3%B5es%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EStephen%20Hawking%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Ciências'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-030-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-030'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'O Gene Egoísta', 'Richard Dawkins', 'BOOKSHARE-031', 'Acervo BookShare', 1976, c.id, 'B-11', 'Exemplar de demonstração da categoria Biologia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%2327613d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%238acb86%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EBIOLOGIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%8C%81%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EO%20Gene%20Ego%C3%ADsta%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ERichard%20Dawkins%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Biologia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-031-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-031'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-031-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-031'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'A Dupla Hélice', 'James D. Watson', 'BOOKSHARE-032', 'Acervo BookShare', 1968, c.id, 'B-12', 'Exemplar de demonstração da categoria Biologia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%2327613d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%238acb86%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EBIOLOGIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%8C%81%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EA%20Dupla%20H%C3%A9lice%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EJames%20D.%20Watson%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Biologia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-032-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-032'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'O Imperador de Todos os Males', 'Siddhartha Mukherjee', 'BOOKSHARE-033', 'Acervo BookShare', 2010, c.id, 'B-13', 'Exemplar de demonstração da categoria Biologia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%2327613d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%238acb86%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EBIOLOGIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%8C%81%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EO%20Imperador%20de%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3ETodos%20os%20Males%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ESiddhartha%20Mukherjee%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Biologia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-033-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-033'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'A Vida Maravilhosa', 'Stephen Jay Gould', 'BOOKSHARE-034', 'Acervo BookShare', 1989, c.id, 'B-14', 'Exemplar de demonstração da categoria Biologia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%2327613d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%238acb86%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EBIOLOGIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%8C%81%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EA%20Vida%20Maravilhosa%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EStephen%20Jay%20Gould%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Biologia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-034-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-034'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'A Canção da Célula', 'Siddhartha Mukherjee', 'BOOKSHARE-035', 'Acervo BookShare', 2022, c.id, 'B-15', 'Exemplar de demonstração da categoria Biologia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%2327613d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%238acb86%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EBIOLOGIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%8C%81%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EA%20Can%C3%A7%C3%A3o%20da%20C%C3%A9lula%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ESiddhartha%20Mukherjee%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Biologia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-035-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-035'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Uma Breve História do Tempo', 'Stephen Hawking', 'BOOKSHARE-036', 'Acervo BookShare', 1988, c.id, 'B-16', 'Exemplar de demonstração da categoria Física. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23243c72%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2391a9f4%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EF%C3%8DSICA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%88%9E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EUma%20Breve%20Hist%C3%B3ria%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3Edo%20Tempo%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EStephen%20Hawking%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Física'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-036-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-036'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-036-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-036'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Seis Peças Fáceis', 'Richard Feynman', 'BOOKSHARE-037', 'Acervo BookShare', 1994, c.id, 'B-17', 'Exemplar de demonstração da categoria Física. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23243c72%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2391a9f4%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EF%C3%8DSICA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%88%9E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3ESeis%20Pe%C3%A7as%20F%C3%A1ceis%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ERichard%20Feynman%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Física'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-037-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-037'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'O Universo Numa Casca de Noz', 'Stephen Hawking', 'BOOKSHARE-038', 'Acervo BookShare', 2001, c.id, 'B-18', 'Exemplar de demonstração da categoria Física. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23243c72%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2391a9f4%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EF%C3%8DSICA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%88%9E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EO%20Universo%20Numa%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3ECasca%20de%20Noz%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EStephen%20Hawking%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Física'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-038-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-038'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Sete Breves Lições de Física', 'Carlo Rovelli', 'BOOKSHARE-039', 'Acervo BookShare', 2014, c.id, 'B-19', 'Exemplar de demonstração da categoria Física. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23243c72%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2391a9f4%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EF%C3%8DSICA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%88%9E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3ESete%20Breves%20Li%C3%A7%C3%B5es%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3Ede%20F%C3%ADsica%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ECarlo%20Rovelli%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Física'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-039-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-039'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Física do Impossível', 'Michio Kaku', 'BOOKSHARE-040', 'Acervo BookShare', 2008, c.id, 'B-20', 'Exemplar de demonstração da categoria Física. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23243c72%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2391a9f4%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EF%C3%8DSICA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%88%9E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EF%C3%ADsica%20do%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EImposs%C3%ADvel%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EMichio%20Kaku%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Física'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-040-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-040'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'A Colher que Desaparece', 'Sam Kean', 'BOOKSHARE-041', 'Acervo BookShare', 2010, c.id, 'C-01', 'Exemplar de demonstração da categoria Química. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%235a3c7a%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23caa5e8%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EQU%C3%8DMICA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%97%89%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EA%20Colher%20que%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EDesaparece%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ESam%20Kean%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Química'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-041-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-041'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-041-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-041'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Tio Tungstênio', 'Oliver Sacks', 'BOOKSHARE-042', 'Acervo BookShare', 2001, c.id, 'C-02', 'Exemplar de demonstração da categoria Química. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%235a3c7a%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23caa5e8%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EQU%C3%8DMICA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%97%89%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3ETio%20Tungst%C3%AAnio%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EOliver%20Sacks%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Química'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-042-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-042'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Os Botões de Napoleão', 'Penny Le Couteur e Jay Burreson', 'BOOKSHARE-043', 'Acervo BookShare', 2003, c.id, 'C-03', 'Exemplar de demonstração da categoria Química. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%235a3c7a%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23caa5e8%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EQU%C3%8DMICA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%97%89%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EOs%20Bot%C3%B5es%20de%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3ENapole%C3%A3o%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EPenny%20Le%20Couteur%20e%20Jay%20Burreson%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Química'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-043-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-043'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'A Tabela Periódica', 'Primo Levi', 'BOOKSHARE-044', 'Acervo BookShare', 1975, c.id, 'C-04', 'Exemplar de demonstração da categoria Química. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%235a3c7a%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23caa5e8%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EQU%C3%8DMICA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%97%89%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EA%20Tabela%20Peri%C3%B3dica%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EPrimo%20Levi%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Química'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-044-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-044'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Química do Cotidiano', 'Equipe Pedagógica BookShare', 'BOOKSHARE-045', 'Acervo BookShare', 2026, c.id, 'C-05', 'Exemplar de demonstração da categoria Química. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%235a3c7a%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23caa5e8%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EQU%C3%8DMICA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%97%89%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EQu%C3%ADmica%20do%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3ECotidiano%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EEquipe%20Pedag%C3%B3gica%20BookShare%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Química'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-045-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-045'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'O Homem que Calculava', 'Malba Tahan', 'BOOKSHARE-046', 'Acervo BookShare', 1938, c.id, 'C-06', 'Exemplar de demonstração da categoria Matemática. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23234f59%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%238bd0c3%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EMATEM%C3%81TICA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%88%91%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EO%20Homem%20que%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3ECalculava%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EMalba%20Tahan%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Matemática'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-046-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-046'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-046-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-046'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'O Último Teorema de Fermat', 'Simon Singh', 'BOOKSHARE-047', 'Acervo BookShare', 1997, c.id, 'C-07', 'Exemplar de demonstração da categoria Matemática. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23234f59%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%238bd0c3%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EMATEM%C3%81TICA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%88%91%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EO%20%C3%9Altimo%20Teorema%20de%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EFermat%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ESimon%20Singh%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Matemática'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-047-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-047'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'O Diabo dos Números', 'Hans Magnus Enzensberger', 'BOOKSHARE-048', 'Acervo BookShare', 1997, c.id, 'C-08', 'Exemplar de demonstração da categoria Matemática. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23234f59%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%238bd0c3%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EMATEM%C3%81TICA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%88%91%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EO%20Diabo%20dos%20N%C3%BAmeros%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EHans%20Magnus%20Enzensberger%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Matemática'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-048-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-048'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Alex no País dos Números', 'Alex Bellos', 'BOOKSHARE-049', 'Acervo BookShare', 2010, c.id, 'C-09', 'Exemplar de demonstração da categoria Matemática. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23234f59%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%238bd0c3%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EMATEM%C3%81TICA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%88%91%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EAlex%20no%20Pa%C3%ADs%20dos%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EN%C3%BAmeros%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EAlex%20Bellos%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Matemática'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-049-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-049'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'A Música dos Números Primos', 'Marcus du Sautoy', 'BOOKSHARE-050', 'Acervo BookShare', 2003, c.id, 'C-10', 'Exemplar de demonstração da categoria Matemática. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23234f59%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%238bd0c3%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EMATEM%C3%81TICA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%88%91%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EA%20M%C3%BAsica%20dos%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EN%C3%BAmeros%20Primos%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EMarcus%20du%20Sautoy%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Matemática'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-050-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-050'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT '1808', 'Laurentino Gomes', 'BOOKSHARE-051', 'Acervo BookShare', 2007, c.id, 'C-11', 'Exemplar de demonstração da categoria História. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23744a2a%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d8af72%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EHIST%C3%93RIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%8C%9B%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3E1808%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ELaurentino%20Gomes%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'História'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-051-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-051'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-051-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-051'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT '1822', 'Laurentino Gomes', 'BOOKSHARE-052', 'Acervo BookShare', 2010, c.id, 'C-12', 'Exemplar de demonstração da categoria História. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23744a2a%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d8af72%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EHIST%C3%93RIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%8C%9B%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3E1822%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ELaurentino%20Gomes%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'História'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-052-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-052'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Brasil: Uma Biografia', 'Lilia Schwarcz e Heloisa Starling', 'BOOKSHARE-053', 'Acervo BookShare', 2015, c.id, 'C-13', 'Exemplar de demonstração da categoria História. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23744a2a%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d8af72%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EHIST%C3%93RIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%8C%9B%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EBrasil%3A%20Uma%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EBiografia%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ELilia%20Schwarcz%20e%20Heloisa%20Starling%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'História'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-053-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-053'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Sapiens', 'Yuval Noah Harari', 'BOOKSHARE-054', 'Acervo BookShare', 2011, c.id, 'C-14', 'Exemplar de demonstração da categoria História. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23744a2a%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d8af72%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EHIST%C3%93RIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%8C%9B%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3ESapiens%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EYuval%20Noah%20Harari%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'História'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-054-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-054'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'A Era dos Extremos', 'Eric Hobsbawm', 'BOOKSHARE-055', 'Acervo BookShare', 1994, c.id, 'C-15', 'Exemplar de demonstração da categoria História. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23744a2a%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d8af72%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EHIST%C3%93RIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%8C%9B%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EA%20Era%20dos%20Extremos%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EEric%20Hobsbawm%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'História'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-055-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-055'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Por uma Outra Globalização', 'Milton Santos', 'BOOKSHARE-056', 'Acervo BookShare', 2000, c.id, 'C-16', 'Exemplar de demonstração da categoria Geografia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%232b6659%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%238fc6a7%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EGEOGRAFIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%97%8E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EPor%20uma%20Outra%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EGlobaliza%C3%A7%C3%A3o%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EMilton%20Santos%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Geografia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-056-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-056'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-056-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-056'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Geografia da Fome', 'Josué de Castro', 'BOOKSHARE-057', 'Acervo BookShare', 1946, c.id, 'C-17', 'Exemplar de demonstração da categoria Geografia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%232b6659%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%238fc6a7%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EGEOGRAFIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%97%8E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EGeografia%20da%20Fome%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EJosu%C3%A9%20de%20Castro%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Geografia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-057-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-057'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Prisioneiros da Geografia', 'Tim Marshall', 'BOOKSHARE-058', 'Acervo BookShare', 2015, c.id, 'C-18', 'Exemplar de demonstração da categoria Geografia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%232b6659%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%238fc6a7%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EGEOGRAFIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%97%8E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EPrisioneiros%20da%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EGeografia%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ETim%20Marshall%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Geografia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-058-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-058'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Armas, Germes e Aço', 'Jared Diamond', 'BOOKSHARE-059', 'Acervo BookShare', 1997, c.id, 'C-19', 'Exemplar de demonstração da categoria Geografia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%232b6659%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%238fc6a7%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EGEOGRAFIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%97%8E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EArmas%2C%20Germes%20e%20A%C3%A7o%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EJared%20Diamond%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Geografia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-059-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-059'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'O Poder da Geografia', 'Tim Marshall', 'BOOKSHARE-060', 'Acervo BookShare', 2021, c.id, 'C-20', 'Exemplar de demonstração da categoria Geografia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%232b6659%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%238fc6a7%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EGEOGRAFIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%97%8E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EO%20Poder%20da%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EGeografia%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ETim%20Marshall%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Geografia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-060-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-060'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'A República', 'Platão', 'BOOKSHARE-061', 'Acervo BookShare', NULL, c.id, 'D-01', 'Exemplar de demonstração da categoria Filosofia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23423d63%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23aaa0db%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EFILOSOFIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%97%87%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EA%20Rep%C3%BAblica%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EPlat%C3%A3o%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Filosofia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-061-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-061'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-061-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-061'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Ética a Nicômaco', 'Aristóteles', 'BOOKSHARE-062', 'Acervo BookShare', NULL, c.id, 'D-02', 'Exemplar de demonstração da categoria Filosofia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23423d63%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23aaa0db%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EFILOSOFIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%97%87%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3E%C3%89tica%20a%20Nic%C3%B4maco%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EArist%C3%B3teles%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Filosofia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-062-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-062'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Discurso do Método', 'René Descartes', 'BOOKSHARE-063', 'Acervo BookShare', 1637, c.id, 'D-03', 'Exemplar de demonstração da categoria Filosofia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23423d63%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23aaa0db%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EFILOSOFIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%97%87%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EDiscurso%20do%20M%C3%A9todo%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ERen%C3%A9%20Descartes%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Filosofia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-063-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-063'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'O Mundo de Sofia', 'Jostein Gaarder', 'BOOKSHARE-064', 'Acervo BookShare', 1991, c.id, 'D-04', 'Exemplar de demonstração da categoria Filosofia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23423d63%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23aaa0db%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EFILOSOFIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%97%87%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EO%20Mundo%20de%20Sofia%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EJostein%20Gaarder%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Filosofia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-064-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-064'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Assim Falou Zaratustra', 'Friedrich Nietzsche', 'BOOKSHARE-065', 'Acervo BookShare', 1883, c.id, 'D-05', 'Exemplar de demonstração da categoria Filosofia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23423d63%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23aaa0db%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EFILOSOFIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%97%87%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EAssim%20Falou%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EZaratustra%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EFriedrich%20Nietzsche%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Filosofia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-065-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-065'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'A Ética Protestante e o Espírito do Capitalismo', 'Max Weber', 'BOOKSHARE-066', 'Acervo BookShare', 1905, c.id, 'D-06', 'Exemplar de demonstração da categoria Sociologia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%237a3e50%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d991a6%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ESOCIOLOGIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%89%A1%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EA%20%C3%89tica%20Protestante%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3Ee%20o%20Esp%C3%ADrito%20do%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3ECapitalismo%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EMax%20Weber%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Sociologia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-066-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-066'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-066-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-066'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'As Regras do Método Sociológico', 'Émile Durkheim', 'BOOKSHARE-067', 'Acervo BookShare', 1895, c.id, 'D-07', 'Exemplar de demonstração da categoria Sociologia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%237a3e50%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d991a6%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ESOCIOLOGIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%89%A1%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EAs%20Regras%20do%20M%C3%A9todo%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3ESociol%C3%B3gico%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3E%C3%89mile%20Durkheim%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Sociologia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-067-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-067'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Casa-Grande & Senzala', 'Gilberto Freyre', 'BOOKSHARE-068', 'Acervo BookShare', 1933, c.id, 'D-08', 'Exemplar de demonstração da categoria Sociologia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%237a3e50%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d991a6%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ESOCIOLOGIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%89%A1%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3ECasa-Grande%20%26amp%3B%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3ESenzala%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EGilberto%20Freyre%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Sociologia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-068-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-068'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Modernidade Líquida', 'Zygmunt Bauman', 'BOOKSHARE-069', 'Acervo BookShare', 2000, c.id, 'D-09', 'Exemplar de demonstração da categoria Sociologia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%237a3e50%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d991a6%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ESOCIOLOGIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%89%A1%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EModernidade%20L%C3%ADquida%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EZygmunt%20Bauman%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Sociologia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-069-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-069'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'O Manifesto Comunista', 'Karl Marx e Friedrich Engels', 'BOOKSHARE-070', 'Acervo BookShare', 1848, c.id, 'D-10', 'Exemplar de demonstração da categoria Sociologia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%237a3e50%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d991a6%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ESOCIOLOGIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%89%A1%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EO%20Manifesto%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EComunista%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EKarl%20Marx%20e%20Friedrich%20Engels%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Sociologia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-070-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-070'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'A História da Arte', 'E. H. Gombrich', 'BOOKSHARE-071', 'Acervo BookShare', 1950, c.id, 'D-11', 'Exemplar de demonstração da categoria Artes. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%238a3c38%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23e7a29a%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EARTES%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%8E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EA%20Hist%C3%B3ria%20da%20Arte%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EE.%20H.%20Gombrich%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Artes'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-071-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-071'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-071-2', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-071'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Modos de Ver', 'John Berger', 'BOOKSHARE-072', 'Acervo BookShare', 1972, c.id, 'D-12', 'Exemplar de demonstração da categoria Artes. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%238a3c38%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23e7a29a%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EARTES%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%8E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EModos%20de%20Ver%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EJohn%20Berger%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Artes'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-072-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-072'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'O Que É Arte?', 'Jorge Coli', 'BOOKSHARE-073', 'Acervo BookShare', 1981, c.id, 'D-13', 'Exemplar de demonstração da categoria Artes. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%238a3c38%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23e7a29a%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EARTES%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%8E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EO%20Que%20%C3%89%20Arte%3F%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EJorge%20Coli%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Artes'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-073-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-073'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Poética', 'Aristóteles', 'BOOKSHARE-074', 'Acervo BookShare', NULL, c.id, 'D-14', 'Exemplar de demonstração da categoria Artes. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%238a3c38%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23e7a29a%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EARTES%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%8E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EPo%C3%A9tica%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EArist%C3%B3teles%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Artes'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-074-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-074'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'A Câmara Clara', 'Roland Barthes', 'BOOKSHARE-075', 'Acervo BookShare', 1980, c.id, 'D-15', 'Exemplar de demonstração da categoria Artes. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%238a3c38%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23e7a29a%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EARTES%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%8E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EA%20C%C3%A2mara%20Clara%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ERoland%20Barthes%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Artes'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-075-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-075'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Os Inovadores', 'Walter Isaacson', 'BOOKSHARE-076', 'Acervo BookShare', 2014, c.id, 'D-16', 'Exemplar de demonstração da categoria Tecnologia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%231d425d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2372a9cf%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ETECNOLOGIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%3C%2F%3E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EOs%20Inovadores%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EWalter%20Isaacson%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Tecnologia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-076-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-076'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Código', 'Charles Petzold', 'BOOKSHARE-077', 'Acervo BookShare', 1999, c.id, 'D-17', 'Exemplar de demonstração da categoria Tecnologia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%231d425d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2372a9cf%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ETECNOLOGIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%3C%2F%3E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EC%C3%B3digo%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ECharles%20Petzold%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Tecnologia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-077-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-077'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Código Limpo', 'Robert C. Martin', 'BOOKSHARE-078', 'Acervo BookShare', 2008, c.id, 'D-18', 'Exemplar de demonstração da categoria Tecnologia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%231d425d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2372a9cf%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ETECNOLOGIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%3C%2F%3E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EC%C3%B3digo%20Limpo%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ERobert%20C.%20Martin%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Tecnologia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-078-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-078'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Algoritmos', 'Thomas Cormen e colaboradores', 'BOOKSHARE-079', 'Acervo BookShare', 1990, c.id, 'D-19', 'Exemplar de demonstração da categoria Tecnologia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%231d425d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2372a9cf%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ETECNOLOGIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%3C%2F%3E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EAlgoritmos%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EThomas%20Cormen%20e%20colaboradores%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Tecnologia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-079-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-079'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Inteligência Artificial: Uma Abordagem Moderna', 'Stuart Russell e Peter Norvig', 'BOOKSHARE-080', 'Acervo BookShare', 1995, c.id, 'D-20', 'Exemplar de demonstração da categoria Tecnologia. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%231d425d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2372a9cf%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3ETECNOLOGIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%3C%2F%3E%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EIntelig%C3%AAncia%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EArtificial%3A%20Uma%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EAbordagem%20Moderna%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EStuart%20Russell%20e%20Peter%20Norvig%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Tecnologia'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-080-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-080'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'O Diário de Anne Frank', 'Anne Frank', 'BOOKSHARE-081', 'Acervo BookShare', 1947, c.id, 'E-01', 'Exemplar de demonstração da categoria Biografias. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%235c5136%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23cfbe7b%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EBIOGRAFIAS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%99%99%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EO%20Di%C3%A1rio%20de%20Anne%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EFrank%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EAnne%20Frank%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Biografias'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-081-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-081'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Longa Caminhada até a Liberdade', 'Nelson Mandela', 'BOOKSHARE-082', 'Acervo BookShare', 1994, c.id, 'E-02', 'Exemplar de demonstração da categoria Biografias. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%235c5136%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23cfbe7b%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EBIOGRAFIAS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%99%99%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3ELonga%20Caminhada%20at%C3%A9%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3Ea%20Liberdade%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3ENelson%20Mandela%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Biografias'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-082-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-082'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Steve Jobs', 'Walter Isaacson', 'BOOKSHARE-083', 'Acervo BookShare', 2011, c.id, 'E-03', 'Exemplar de demonstração da categoria Biografias. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%235c5136%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23cfbe7b%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EBIOGRAFIAS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%99%99%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3ESteve%20Jobs%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EWalter%20Isaacson%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Biografias'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-083-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-083'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Minha História', 'Michelle Obama', 'BOOKSHARE-084', 'Acervo BookShare', 2018, c.id, 'E-04', 'Exemplar de demonstração da categoria Biografias. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%235c5136%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23cfbe7b%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EBIOGRAFIAS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%99%99%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EMinha%20Hist%C3%B3ria%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EMichelle%20Obama%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Biografias'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-084-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-084'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Eu Sou Malala', 'Malala Yousafzai', 'BOOKSHARE-085', 'Acervo BookShare', 2013, c.id, 'E-05', 'Exemplar de demonstração da categoria Biografias. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%235c5136%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23cfbe7b%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EBIOGRAFIAS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%99%99%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EEu%20Sou%20Malala%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EMalala%20Yousafzai%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Biografias'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-085-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-085'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Maus', 'Art Spiegelman', 'BOOKSHARE-086', 'Acervo BookShare', 1986, c.id, 'E-06', 'Exemplar de demonstração da categoria Quadrinhos. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23713e7d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d395df%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EQUADRINHOS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%21%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EMaus%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EArt%20Spiegelman%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Quadrinhos'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-086-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-086'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Persépolis', 'Marjane Satrapi', 'BOOKSHARE-087', 'Acervo BookShare', 2000, c.id, 'E-07', 'Exemplar de demonstração da categoria Quadrinhos. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23713e7d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d395df%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EQUADRINHOS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%21%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EPers%C3%A9polis%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EMarjane%20Satrapi%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Quadrinhos'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-087-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-087'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Watchmen', 'Alan Moore e Dave Gibbons', 'BOOKSHARE-088', 'Acervo BookShare', 1987, c.id, 'E-08', 'Exemplar de demonstração da categoria Quadrinhos. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23713e7d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d395df%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EQUADRINHOS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%21%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EWatchmen%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EAlan%20Moore%20e%20Dave%20Gibbons%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Quadrinhos'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-088-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-088'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Turma da Mônica: Laços', 'Vitor e Lu Cafaggi', 'BOOKSHARE-089', 'Acervo BookShare', 2013, c.id, 'E-09', 'Exemplar de demonstração da categoria Quadrinhos. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23713e7d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d395df%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EQUADRINHOS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%21%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3ETurma%20da%20M%C3%B4nica%3A%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3ELa%C3%A7os%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EVitor%20e%20Lu%20Cafaggi%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Quadrinhos'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-089-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-089'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Daytripper', 'Fábio Moon e Gabriel Bá', 'BOOKSHARE-090', 'Acervo BookShare', 2010, c.id, 'E-10', 'Exemplar de demonstração da categoria Quadrinhos. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23713e7d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%23d395df%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EQUADRINHOS%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%21%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EDaytripper%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EF%C3%A1bio%20Moon%20e%20Gabriel%20B%C3%A1%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Quadrinhos'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-090-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-090'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Guia de Redação ENEM', 'Equipe Pedagógica BookShare', 'BOOKSHARE-091', 'Acervo BookShare', 2026, c.id, 'E-11', 'Exemplar de demonstração da categoria Vestibular e ENEM. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23126b5d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2377cbb8%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EVESTIBULAR%20E%20ENEM%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%93%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EGuia%20de%20Reda%C3%A7%C3%A3o%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EENEM%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EEquipe%20Pedag%C3%B3gica%20BookShare%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Vestibular e ENEM'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-091-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-091'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Matemática Essencial para o ENEM', 'Equipe Pedagógica BookShare', 'BOOKSHARE-092', 'Acervo BookShare', 2026, c.id, 'E-12', 'Exemplar de demonstração da categoria Vestibular e ENEM. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23126b5d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2377cbb8%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EVESTIBULAR%20E%20ENEM%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%93%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EMatem%C3%A1tica%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EEssencial%20para%20o%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EENEM%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EEquipe%20Pedag%C3%B3gica%20BookShare%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Vestibular e ENEM'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-092-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-092'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Ciências da Natureza em Revisão', 'Equipe Pedagógica BookShare', 'BOOKSHARE-093', 'Acervo BookShare', 2026, c.id, 'E-13', 'Exemplar de demonstração da categoria Vestibular e ENEM. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23126b5d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2377cbb8%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EVESTIBULAR%20E%20ENEM%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%93%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3ECi%C3%AAncias%20da%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3ENatureza%20em%20Revis%C3%A3o%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EEquipe%20Pedag%C3%B3gica%20BookShare%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Vestibular e ENEM'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-093-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-093'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Ciências Humanas em Revisão', 'Equipe Pedagógica BookShare', 'BOOKSHARE-094', 'Acervo BookShare', 2026, c.id, 'E-14', 'Exemplar de demonstração da categoria Vestibular e ENEM. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23126b5d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2377cbb8%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EVESTIBULAR%20E%20ENEM%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%93%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3ECi%C3%AAncias%20Humanas%20em%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3ERevis%C3%A3o%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EEquipe%20Pedag%C3%B3gica%20BookShare%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Vestibular e ENEM'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-094-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-094'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Linguagens e Literatura para Vestibulares', 'Equipe Pedagógica BookShare', 'BOOKSHARE-095', 'Acervo BookShare', 2026, c.id, 'E-15', 'Exemplar de demonstração da categoria Vestibular e ENEM. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23126b5d%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2377cbb8%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EVESTIBULAR%20E%20ENEM%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3E%E2%9C%93%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3ELinguagens%20e%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3ELiteratura%20para%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EVestibulares%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EEquipe%20Pedag%C3%B3gica%20BookShare%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Vestibular e ENEM'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-095-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-095'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Dicionário Escolar da Língua Portuguesa', 'Equipe Lexicográfica BookShare', 'BOOKSHARE-096', 'Acervo BookShare', 2026, c.id, 'E-16', 'Exemplar de demonstração da categoria Dicionários e Referência. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23334e68%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2393b5d1%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EDICION%C3%81RIOS%20E%20REFER%C3%8ANCIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3EA%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EDicion%C3%A1rio%20Escolar%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3Eda%20L%C3%ADngua%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EPortuguesa%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EEquipe%20Lexicogr%C3%A1fica%20BookShare%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Dicionários e Referência'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-096-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-096'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Atlas Geográfico Escolar', 'Equipe Geográfica BookShare', 'BOOKSHARE-097', 'Acervo BookShare', 2026, c.id, 'E-17', 'Exemplar de demonstração da categoria Dicionários e Referência. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23334e68%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2393b5d1%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EDICION%C3%81RIOS%20E%20REFER%C3%8ANCIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3EA%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EAtlas%20Geogr%C3%A1fico%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EEscolar%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EEquipe%20Geogr%C3%A1fica%20BookShare%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Dicionários e Referência'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-097-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-097'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Gramática de Consulta', 'Equipe Pedagógica BookShare', 'BOOKSHARE-098', 'Acervo BookShare', 2026, c.id, 'E-18', 'Exemplar de demonstração da categoria Dicionários e Referência. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23334e68%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2393b5d1%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EDICION%C3%81RIOS%20E%20REFER%C3%8ANCIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3EA%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EGram%C3%A1tica%20de%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EConsulta%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EEquipe%20Pedag%C3%B3gica%20BookShare%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Dicionários e Referência'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-098-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-098'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Enciclopédia de Ciências', 'Equipe Científica BookShare', 'BOOKSHARE-099', 'Acervo BookShare', 2026, c.id, 'E-19', 'Exemplar de demonstração da categoria Dicionários e Referência. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23334e68%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2393b5d1%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EDICION%C3%81RIOS%20E%20REFER%C3%8ANCIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3EA%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EEnciclop%C3%A9dia%20de%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3ECi%C3%AAncias%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EEquipe%20Cient%C3%ADfica%20BookShare%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Dicionários e Referência'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-099-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-099'
ON CONFLICT (inventory_code) DO NOTHING;
INSERT INTO books (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, active)
SELECT 'Dicionário Português–Inglês', 'Equipe Lexicográfica BookShare', 'BOOKSHARE-100', 'Acervo BookShare', 2026, c.id, 'E-20', 'Exemplar de demonstração da categoria Dicionários e Referência. Capa temática gerada para o catálogo BookShare.', 'data:image/svg+xml;charset=UTF-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22420%22%20height%3D%22640%22%20viewBox%3D%220%200%20420%20640%22%3E%3Cdefs%3E%3ClinearGradient%20id%3D%22g%22%20x1%3D%220%22%20y1%3D%220%22%20x2%3D%221%22%20y2%3D%221%22%3E%3Cstop%20stop-color%3D%22%23334e68%22%2F%3E%3Cstop%20offset%3D%221%22%20stop-color%3D%22%2393b5d1%22%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20width%3D%22420%22%20height%3D%22640%22%20rx%3D%2218%22%20fill%3D%22url%28%23g%29%22%2F%3E%3Crect%20x%3D%2222%22%20y%3D%2222%22%20width%3D%22376%22%20height%3D%22596%22%20rx%3D%2212%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.3%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%2268%22%20fill%3D%22white%22%20fill-opacity%3D%22.8%22%20font-family%3D%22Arial%22%20font-size%3D%2218%22%20letter-spacing%3D%222%22%3EDICION%C3%81RIOS%20E%20REFER%C3%8ANCIA%3C%2Ftext%3E%3Ctext%20x%3D%22330%22%20y%3D%22125%22%20text-anchor%3D%22middle%22%20fill%3D%22white%22%20fill-opacity%3D%22.2%22%20font-family%3D%22Georgia%22%20font-size%3D%22120%22%3EA%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22250%22%20fill%3D%22white%22%20font-family%3D%22Georgia%22%20font-size%3D%2236%22%20font-weight%3D%22700%22%3E%3Ctspan%20x%3D%2244%22%20dy%3D%220%22%3EDicion%C3%A1rio%3C%2Ftspan%3E%3Ctspan%20x%3D%2244%22%20dy%3D%2240%22%3EPortugu%C3%AAs%E2%80%93Ingl%C3%AAs%3C%2Ftspan%3E%3C%2Ftext%3E%3Cline%20x1%3D%2244%22%20y1%3D%22490%22%20x2%3D%22190%22%20y2%3D%22490%22%20stroke%3D%22white%22%20stroke-opacity%3D%22.55%22%2F%3E%3Ctext%20x%3D%2244%22%20y%3D%22530%22%20fill%3D%22white%22%20font-family%3D%22Arial%22%20font-size%3D%2221%22%3EEquipe%20Lexicogr%C3%A1fica%20BookShare%3C%2Ftext%3E%3Ctext%20x%3D%2244%22%20y%3D%22590%22%20fill%3D%22white%22%20fill-opacity%3D%22.7%22%20font-family%3D%22Arial%22%20font-size%3D%2216%22%3EBOOKSHARE%20%E2%80%A2%20ACERVO%20ESCOLAR%3C%2Ftext%3E%3C%2Fsvg%3E', TRUE
FROM categories c WHERE c.name = 'Dicionários e Referência'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title, author = EXCLUDED.author, category_id = EXCLUDED.category_id, shelf = EXCLUDED.shelf, description = EXCLUDED.description, cover_url = EXCLUDED.cover_url, active = TRUE, updated_at = NOW();
INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT b.id, 'BS-DEMO-100-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo' FROM books b WHERE b.isbn = 'BOOKSHARE-100'
ON CONFLICT (inventory_code) DO NOTHING;



-- As capas SVG de demonstração são removidas para que a aplicação carregue
-- automaticamente capas reais pelo Google Books, pesquisando título e autor.
UPDATE books
SET cover_url = NULL,
    updated_at = NOW()
WHERE isbn LIKE 'BOOKSHARE-%'
  AND (
    cover_url IS NULL
    OR cover_url LIKE 'data:image/svg+xml%'
    OR cover_url LIKE '%openlibrary.org%'
  );

-- Fotografias iniciais dos dois perfis.
UPDATE users
SET avatar_url = 'https://randomuser.me/api/portraits/men/32.jpg',
    updated_at = NOW()
WHERE email = 'admin@bookshare.com';

UPDATE users
SET avatar_url = 'https://randomuser.me/api/portraits/women/44.jpg',
    updated_at = NOW()
WHERE email = 'biblioteca@bookshare.com';

-- ============================================================================
-- BOOKSHARE V36 — INTEGRAÇÃO FINAL
-- Escolas, vínculos de perfil, capas manuais e catálogo demonstrativo de 50 livros.
-- ============================================================================

CREATE TABLE IF NOT EXISTS schools (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(140) NOT NULL,
  code VARCHAR(30) NOT NULL UNIQUE,
  address VARCHAR(220),
  contact_email VARCHAR(180),
  phone VARCHAR(40),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS school_id UUID;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(40);
ALTER TABLE users ADD COLUMN IF NOT EXISTS job_title VARCHAR(80);
ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS system_key VARCHAR(60);
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_changed_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS system_migrations (
  migration_key VARCHAR(140) PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS users_system_key_unique
  ON users (system_key)
  WHERE system_key IS NOT NULL;

ALTER TABLE students ADD COLUMN IF NOT EXISTS school_id UUID;
ALTER TABLE classes ADD COLUMN IF NOT EXISTS school_id UUID;
ALTER TABLE books ADD COLUMN IF NOT EXISTS school_id UUID;
ALTER TABLE books ADD COLUMN IF NOT EXISTS cover_source TEXT;
ALTER TABLE books ADD COLUMN IF NOT EXISTS cover_checked_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS users_school_id_idx ON users (school_id);
CREATE INDEX IF NOT EXISTS students_school_id_idx ON students (school_id);
CREATE INDEX IF NOT EXISTS classes_school_id_idx ON classes (school_id);
CREATE INDEX IF NOT EXISTS books_school_id_idx ON books (school_id);
CREATE INDEX IF NOT EXISTS books_cover_source_idx ON books (cover_source);
CREATE INDEX IF NOT EXISTS users_deleted_at_idx ON users (deleted_at);

DROP TRIGGER IF EXISTS schools_set_updated_at ON schools;
CREATE TRIGGER schools_set_updated_at
BEFORE UPDATE ON schools
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

INSERT INTO schools (name, code, contact_email, phone, active)
SELECT school_name, 'PRINCIPAL', contact_email, contact_phone, TRUE
FROM settings
WHERE id = 1
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  contact_email = COALESCE(EXCLUDED.contact_email, schools.contact_email),
  phone = COALESCE(EXCLUDED.phone, schools.phone),
  active = TRUE,
  updated_at = NOW();

UPDATE users
SET school_id = (SELECT id FROM schools WHERE code = 'PRINCIPAL' LIMIT 1),
    job_title = CASE WHEN role = 'admin' THEN 'Administrador do sistema' ELSE 'Bibliotecária' END,
    updated_at = NOW()
WHERE school_id IS NULL;

UPDATE classes
SET school_id = (SELECT id FROM schools WHERE code = 'PRINCIPAL' LIMIT 1),
    updated_at = NOW()
WHERE school_id IS NULL;

UPDATE students s
SET school_id = COALESCE(c.school_id, (SELECT id FROM schools WHERE code = 'PRINCIPAL' LIMIT 1)),
    updated_at = NOW()
FROM classes c
WHERE s.class_id = c.id
  AND s.school_id IS NULL;

UPDATE books
SET school_id = (SELECT id FROM schools WHERE code = 'PRINCIPAL' LIMIT 1),
    updated_at = NOW()
WHERE school_id IS NULL;

-- Garante que as duas contas oficiais não sejam misturadas.
UPDATE users
SET email = LOWER(TRIM(email)),
    role = 'admin'::user_role,
    active = TRUE,
    deleted_at = NULL,
    system_key = 'bookshare-admin',
    job_title = COALESCE(NULLIF(TRIM(job_title), ''), 'Administrador do sistema'),
    updated_at = NOW()
WHERE LOWER(TRIM(email)) = 'admin@bookshare.com';

UPDATE users
SET email = LOWER(TRIM(email)),
    role = 'librarian'::user_role,
    active = TRUE,
    deleted_at = NULL,
    system_key = 'bookshare-librarian',
    job_title = COALESCE(NULLIF(TRIM(job_title), ''), 'Bibliotecária'),
    updated_at = NOW()
WHERE LOWER(TRIM(email)) = 'biblioteca@bookshare.com';

-- Livro solicitado que não existia no catálogo original.
INSERT INTO books (
  title, author, isbn, publisher, publication_year, category_id, shelf,
  description, cover_url, cover_source, cover_checked_at, school_id, active
)
SELECT
  'Quarto de Despejo',
  'Carolina Maria de Jesus',
  'BOOKSHARE-101',
  'Acervo BookShare',
  1960,
  c.id,
  'A-06',
  'Diário de Carolina Maria de Jesus, obra fundamental da literatura brasileira.',
  'data:image/jpeg;base64,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KWxYktwSe/Jjs6eHpuS0FLbjcBvThdge259PpN81NbaRxxX4S3BU+lSVJ4PxB/ZJbdZYnGxRScYAHOTsAAK9fo7fhqaX6iSG9Kbm3eoAghWbcVAvaBZPtdEiOzpp1OlbGQGFEi+CD/Amj8u80yTrtYcpUkKNo2gC+1k+5J4ugPYAD2kabGUiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgZ4sLMaVWY/BQT/AAmQ0zlioRtw7rtNj6irE6voZA0DbWzBsmashwJvetvC9wVB+Pzr3ljrPNYadSNUN3oRMbAMNh27tRlo21812HMi59rmHT59Eu/GjIdZm2e20MR7sFFn633+YMpJcu5tFmroiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgXeFdMgOzU5VYki1V1scVdDkd/2zHA2FSFGqyjGQxbaHXniuAK55PyqU0TOLeSbrsWEAnHlLkt2KsOKJJJI+ND53IURNjKREQEREBERAREQEREBERAREQEREBERAREQEREBERAREQEREBERAREQERED/2Q==',
  'manual-upload',
  NOW(),
  (SELECT id FROM schools WHERE code = 'PRINCIPAL' LIMIT 1),
  TRUE
FROM categories c
WHERE c.name = 'Literatura Brasileira'
ON CONFLICT (isbn) DO UPDATE SET
  title = EXCLUDED.title,
  author = EXCLUDED.author,
  publisher = EXCLUDED.publisher,
  publication_year = EXCLUDED.publication_year,
  category_id = EXCLUDED.category_id,
  shelf = EXCLUDED.shelf,
  description = EXCLUDED.description,
  cover_url = EXCLUDED.cover_url,
  cover_source = 'manual-upload',
  cover_checked_at = NOW(),
  school_id = EXCLUDED.school_id,
  active = TRUE,
  updated_at = NOW();

INSERT INTO book_copies (book_id, inventory_code, status, acquired_at, condition_notes)
SELECT id, 'BS-DEMO-101-1', 'available', CURRENT_DATE, 'Exemplar inicial do acervo'
FROM books
WHERE isbn = 'BOOKSHARE-101'
ON CONFLICT (inventory_code) DO NOTHING;

-- Capas reais enviadas pelo usuário. O marcador manual-upload impede substituição automática.
UPDATE books
SET cover_url = 'data:image/jpeg;base64,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',
    cover_source = 'manual-upload',
    cover_checked_at = NOW(),
    updated_at = NOW()
WHERE LOWER(TRIM(title)) = LOWER(TRIM('A República'));

UPDATE books
SET cover_url = 'data:image/jpeg;base64,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',
    cover_source = 'manual-upload',
    cover_checked_at = NOW(),
    updated_at = NOW()
WHERE LOWER(TRIM(title)) = LOWER(TRIM('Antologia Poética'));

UPDATE books
SET cover_url = 'data:image/jpeg;base64,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',
    cover_source = 'manual-upload',
    cover_checked_at = NOW(),
    updated_at = NOW()
WHERE LOWER(TRIM(title)) = LOWER(TRIM('Cosmos'));

UPDATE books
SET cover_url = 'data:image/jpeg;base64,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',
    cover_source = 'manual-upload',
    cover_checked_at = NOW(),
    updated_at = NOW()
WHERE LOWER(TRIM(title)) = LOWER(TRIM('O Mágico de Oz'));

UPDATE books
SET cover_url = 'data:image/jpeg;base64,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',
    cover_source = 'manual-upload',
    cover_checked_at = NOW(),
    updated_at = NOW()
WHERE LOWER(TRIM(title)) = LOWER(TRIM('O Mundo Assombrado pelos Demônios'));

UPDATE books
SET cover_url = 'data:image/jpeg;base64,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KWxYktwSe/Jjs6eHpuS0FLbjcBvThdge259PpN81NbaRxxX4S3BU+lSVJ4PxB/ZJbdZYnGxRScYAHOTsAAK9fo7fhqaX6iSG9Kbm3eoAghWbcVAvaBZPtdEiOzpp1OlbGQGFEi+CD/Amj8u80yTrtYcpUkKNo2gC+1k+5J4ugPYAD2kabGUiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgZ4sLMaVWY/BQT/AAmQ0zlioRtw7rtNj6irE6voZA0DbWzBsmashwJvetvC9wVB+Pzr3ljrPNYadSNUN3oRMbAMNh27tRlo21812HMi59rmHT59Eu/GjIdZm2e20MR7sFFn633+YMpJcu5tFmroiIgIiICIiAiIgIiICIiAiIgIiICIiAiIgXeFdMgOzU5VYki1V1scVdDkd/2zHA2FSFGqyjGQxbaHXniuAK55PyqU0TOLeSbrsWEAnHlLkt2KsOKJJJI+ND53IURNjKREQEREBERAREQEREBERAREQEREBERAREQEREBERAREQEREBERAREQERED/2Q==',
    cover_source = 'manual-upload',
    cover_checked_at = NOW(),
    updated_at = NOW()
WHERE LOWER(TRIM(title)) = LOWER(TRIM('Quarto de Despejo'));

-- Mantém exatamente 50 títulos demonstrativos ativos no catálogo.
UPDATE books
SET active = CASE
  WHEN title IN (
  'Dom Casmurro',
  'Memórias Póstumas de Brás Cubas',
  'O Cortiço',
  'Vidas Secas',
  'Capitães da Areia',
  'Quarto de Despejo',
  'Crime e Castigo',
  'Guerra e Paz',
  'Anna Kariênina',
  'O Mestre e Margarida',
  'O Pequeno Príncipe',
  'Alice no País das Maravilhas',
  'As Aventuras de Tom Sawyer',
  'O Mágico de Oz',
  'A Ilha do Tesouro',
  'Alguma Poesia',
  'Mensagem',
  'Antologia Poética',
  'Romanceiro da Inconfidência',
  'Laços de Família',
  'Morangos Mofados',
  'Contos Novos',
  'Primeiras Estórias',
  'O Alienista',
  'Cosmos',
  'O Mundo Assombrado pelos Demônios',
  'A Origem das Espécies',
  'Primavera Silenciosa',
  'Breves Respostas para Grandes Questões',
  'O Gene Egoísta',
  'Uma Breve História do Tempo',
  'Sete Breves Lições de Física',
  'A Colher que Desaparece',
  'A Tabela Periódica',
  'O Homem que Calculava',
  'O Último Teorema de Fermat',
  'O Diabo dos Números',
  'A Música dos Números Primos',
  '1808',
  'Brasil: Uma Biografia',
  'Sapiens',
  'A Era dos Extremos',
  'Prisioneiros da Geografia',
  'Geografia da Fome',
  'A República',
  'O Mundo de Sofia',
  'Ética a Nicômaco',
  'Modernidade Líquida',
  'Código Limpo',
  'Maus'
  ) THEN TRUE
  ELSE FALSE
END,
updated_at = NOW()
WHERE isbn LIKE 'BOOKSHARE-%';

-- Conferência final da instalação.
DO $$
DECLARE
  active_demo_count INTEGER;
BEGIN
  SELECT COUNT(*)::INTEGER INTO active_demo_count
  FROM books
  WHERE active = TRUE
    AND isbn LIKE 'BOOKSHARE-%';

  IF active_demo_count <> 50 THEN
    RAISE EXCEPTION 'O catálogo demonstrativo deveria ter 50 livros ativos, mas possui %.', active_demo_count;
  END IF;
END
$$;

COMMIT;
