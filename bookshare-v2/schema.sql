-- Schema isolado da V2, execute SOMENTE em um banco novo.
BEGIN;
CREATE SCHEMA IF NOT EXISTS bookshare_v2;
SET LOCAL search_path TO bookshare_v2, public;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(120) NOT NULL,
  email VARCHAR(180) NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('admin','librarian')),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS media_assets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mime TEXT NOT NULL CHECK (mime IN ('image/webp')),
  data BYTEA NOT NULL,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS students (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(160) NOT NULL,
  registration VARCHAR(60) NOT NULL UNIQUE,
  class_name VARCHAR(80) NOT NULL,
  contact VARCHAR(120) NOT NULL DEFAULT '',
  photo_id UUID REFERENCES media_assets(id) ON DELETE SET NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS books (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title VARCHAR(180) NOT NULL,
  author VARCHAR(160) NOT NULL,
  isbn VARCHAR(20) UNIQUE,
  category VARCHAR(80) NOT NULL DEFAULT 'Geral',
  cover_id UUID REFERENCES media_assets(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS copies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id UUID NOT NULL REFERENCES books(id) ON DELETE RESTRICT,
  code VARCHAR(60) NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'available' CHECK(status IN ('available','loaned','damaged','lost')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS loans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE RESTRICT,
  copy_id UUID NOT NULL REFERENCES copies(id) ON DELETE RESTRICT,
  issued_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  loaned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  due_date DATE NOT NULL,
  returned_at TIMESTAMPTZ,
  return_condition TEXT CHECK(return_condition IN ('normal','damaged','lost')),
  renewals SMALLINT NOT NULL DEFAULT 0 CHECK(renewals BETWEEN 0 AND 2),
  status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','returned'))
);
CREATE UNIQUE INDEX IF NOT EXISTS one_active_loan_per_copy ON loans(copy_id) WHERE status='active';
CREATE INDEX IF NOT EXISTS loans_by_due ON loans(due_date) WHERE status='active';
CREATE TABLE IF NOT EXISTS reservations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE RESTRICT,
  book_id UUID NOT NULL REFERENCES books(id) ON DELETE RESTRICT,
  created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  status TEXT NOT NULL DEFAULT 'waiting' CHECK(status IN ('waiting','ready','completed','cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS one_reservation_per_student_book ON reservations(student_id,book_id)
  WHERE status IN ('waiting','ready');

-- Somente a API Node autenticada acessa as tabelas: nada é liberado à Data API pública.
REVOKE ALL ON SCHEMA bookshare_v2 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL TABLES IN SCHEMA bookshare_v2 FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA bookshare_v2 REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated;
COMMIT;
