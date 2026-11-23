-- Migração reversível por backup: preserva alunos, livros, empréstimos e contas existentes.
BEGIN;
CREATE TABLE IF NOT EXISTS bookshare_v2.schools (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 name VARCHAR(160) NOT NULL, city VARCHAR(100) NOT NULL,
 state CHAR(2) NOT NULL DEFAULT 'PR', address VARCHAR(220) NOT NULL DEFAULT '',
 phone VARCHAR(40) NOT NULL DEFAULT '', email VARCHAR(180) NOT NULL DEFAULT '',
 active BOOLEAN NOT NULL DEFAULT TRUE, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO bookshare_v2.schools(id,name,city,state)
VALUES ('00000000-0000-4000-8000-000000000010','Colégio Helena Wysocki','Araucária','PR') ON CONFLICT(id) DO NOTHING;
ALTER TABLE bookshare_v2.users ADD COLUMN IF NOT EXISTS school_id UUID REFERENCES bookshare_v2.schools(id);
UPDATE bookshare_v2.users SET school_id='00000000-0000-4000-8000-000000000010' WHERE school_id IS NULL;
ALTER TABLE bookshare_v2.users ALTER COLUMN school_id SET NOT NULL;
ALTER TABLE bookshare_v2.users ALTER COLUMN school_id SET DEFAULT '00000000-0000-4000-8000-000000000010';
ALTER TABLE bookshare_v2.media_assets ADD COLUMN IF NOT EXISTS school_id UUID REFERENCES bookshare_v2.schools(id);
UPDATE bookshare_v2.media_assets SET school_id='00000000-0000-4000-8000-000000000010' WHERE school_id IS NULL;
ALTER TABLE bookshare_v2.media_assets ALTER COLUMN school_id SET NOT NULL;
ALTER TABLE bookshare_v2.media_assets ALTER COLUMN school_id SET DEFAULT '00000000-0000-4000-8000-000000000010';
ALTER TABLE bookshare_v2.students ADD COLUMN IF NOT EXISTS school_id UUID REFERENCES bookshare_v2.schools(id);
UPDATE bookshare_v2.students SET school_id='00000000-0000-4000-8000-000000000010' WHERE school_id IS NULL;
ALTER TABLE bookshare_v2.students ALTER COLUMN school_id SET NOT NULL;
ALTER TABLE bookshare_v2.students ALTER COLUMN school_id SET DEFAULT '00000000-0000-4000-8000-000000000010';
ALTER TABLE bookshare_v2.books ADD COLUMN IF NOT EXISTS school_id UUID REFERENCES bookshare_v2.schools(id);
UPDATE bookshare_v2.books SET school_id='00000000-0000-4000-8000-000000000010' WHERE school_id IS NULL;
ALTER TABLE bookshare_v2.books ALTER COLUMN school_id SET NOT NULL;
ALTER TABLE bookshare_v2.books ALTER COLUMN school_id SET DEFAULT '00000000-0000-4000-8000-000000000010';
ALTER TABLE bookshare_v2.copies ADD COLUMN IF NOT EXISTS school_id UUID REFERENCES bookshare_v2.schools(id);
UPDATE bookshare_v2.copies SET school_id='00000000-0000-4000-8000-000000000010' WHERE school_id IS NULL;
ALTER TABLE bookshare_v2.copies ALTER COLUMN school_id SET NOT NULL;
ALTER TABLE bookshare_v2.copies ALTER COLUMN school_id SET DEFAULT '00000000-0000-4000-8000-000000000010';
ALTER TABLE bookshare_v2.loans ADD COLUMN IF NOT EXISTS school_id UUID REFERENCES bookshare_v2.schools(id);
UPDATE bookshare_v2.loans SET school_id='00000000-0000-4000-8000-000000000010' WHERE school_id IS NULL;
ALTER TABLE bookshare_v2.loans ALTER COLUMN school_id SET NOT NULL;
ALTER TABLE bookshare_v2.loans ALTER COLUMN school_id SET DEFAULT '00000000-0000-4000-8000-000000000010';
ALTER TABLE bookshare_v2.reservations ADD COLUMN IF NOT EXISTS school_id UUID REFERENCES bookshare_v2.schools(id);
UPDATE bookshare_v2.reservations SET school_id='00000000-0000-4000-8000-000000000010' WHERE school_id IS NULL;
ALTER TABLE bookshare_v2.reservations ALTER COLUMN school_id SET NOT NULL;
ALTER TABLE bookshare_v2.reservations ALTER COLUMN school_id SET DEFAULT '00000000-0000-4000-8000-000000000010';
ALTER TABLE bookshare_v2.students DROP CONSTRAINT IF EXISTS students_registration_key;
ALTER TABLE bookshare_v2.books DROP CONSTRAINT IF EXISTS books_isbn_key;
ALTER TABLE bookshare_v2.copies DROP CONSTRAINT IF EXISTS copies_code_key;
CREATE UNIQUE INDEX IF NOT EXISTS students_school_registration ON bookshare_v2.students(school_id,registration);
CREATE UNIQUE INDEX IF NOT EXISTS books_school_isbn ON bookshare_v2.books(school_id,isbn);
CREATE UNIQUE INDEX IF NOT EXISTS copies_school_code ON bookshare_v2.copies(school_id,code);
CREATE UNIQUE INDEX IF NOT EXISTS students_id_school ON bookshare_v2.students(id,school_id);
CREATE UNIQUE INDEX IF NOT EXISTS books_id_school ON bookshare_v2.books(id,school_id);
CREATE UNIQUE INDEX IF NOT EXISTS copies_id_school ON bookshare_v2.copies(id,school_id);
ALTER TABLE bookshare_v2.copies ADD CONSTRAINT copies_book_same_school FOREIGN KEY(book_id,school_id) REFERENCES bookshare_v2.books(id,school_id);
ALTER TABLE bookshare_v2.loans ADD CONSTRAINT loans_student_same_school FOREIGN KEY(student_id,school_id) REFERENCES bookshare_v2.students(id,school_id);
ALTER TABLE bookshare_v2.loans ADD CONSTRAINT loans_copy_same_school FOREIGN KEY(copy_id,school_id) REFERENCES bookshare_v2.copies(id,school_id);
ALTER TABLE bookshare_v2.reservations ADD CONSTRAINT reservations_student_same_school FOREIGN KEY(student_id,school_id) REFERENCES bookshare_v2.students(id,school_id);
ALTER TABLE bookshare_v2.reservations ADD CONSTRAINT reservations_book_same_school FOREIGN KEY(book_id,school_id) REFERENCES bookshare_v2.books(id,school_id);
REVOKE ALL ON TABLE bookshare_v2.schools FROM PUBLIC, anon, authenticated;
COMMIT;