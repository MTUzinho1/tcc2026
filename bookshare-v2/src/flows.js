// Regras isoladas para operações críticas, sem depender de interface.
export class DomainError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}
export function requiredText(value, label, max = 160) {
  const out = String(value ?? "").trim();
  if (!out || out.length > max) throw new DomainError(`${label}: informe entre 1 e ${max} caracteres.`);
  return out;
}
export function optionalText(value, max = 160) {
  const out = String(value ?? "").trim();
  if (out.length > max) throw new DomainError(`Texto muito longo (máximo ${max} caracteres).`);
  return out;
}
export function validUuid(value) {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(value ?? ""))) throw new DomainError("Identificador inválido.");
  return value;
}
export function validDueDate(value, today = new Date()) {
  const due = String(value ?? "");
  const parsed = new Date(due + "T12:00:00Z");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(due) || Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0,10) !== due) {
    throw new DomainError("Data de devolução inválida.");
  }
  const base = today.toISOString().slice(0, 10);
  if (due < base) throw new DomainError("A devolução não pode vencer no passado.");
  return due;
}
export async function transact(pool, callback) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await callback(client);
    await client.query("COMMIT");
    return result;
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally { client.release(); }
}
export async function createLoan(pool, { studentId, copyId, dueDate, userId, schoolId }) {
  validUuid(schoolId);
  validUuid(studentId); validUuid(copyId);
  const due = validDueDate(dueDate);
  return transact(pool, async (db) => {
    const student = await db.query("SELECT active FROM bookshare_v2.students WHERE id=$1 AND school_id=$2", [studentId,schoolId]);
    if (!student.rowCount || !student.rows[0].active) throw new DomainError("Aluno não encontrado ou inativo.", 404);
    const parent = await db.query("SELECT book_id FROM bookshare_v2.copies WHERE id=$1 AND school_id=$2", [copyId,schoolId]);
    if (!parent.rowCount) throw new DomainError("Exemplar não encontrado.", 404);
    await db.query("SELECT id FROM bookshare_v2.books WHERE id=$1 AND school_id=$2 FOR UPDATE", [parent.rows[0].book_id,schoolId]);
    const copy = await db.query("SELECT status FROM bookshare_v2.copies WHERE id=$1 AND school_id=$2 FOR UPDATE", [copyId,schoolId]);
    if (copy.rows[0].status !== "available") throw new DomainError("Exemplar indisponível para empréstimo.", 409);
    const ready = await db.query("SELECT student_id FROM bookshare_v2.reservations WHERE book_id=$1 AND school_id=$2 AND status='ready' ORDER BY created_at LIMIT 1", [parent.rows[0].book_id,schoolId]);
    if (ready.rowCount && ready.rows[0].student_id !== studentId) throw new DomainError("Exemplar reservado para outro aluno.", 409);
    const loan = await db.query(
      "INSERT INTO bookshare_v2.loans(student_id,copy_id,due_date,issued_by,school_id) VALUES($1,$2,$3,$4,$5) RETURNING *",
      [studentId, copyId, due, userId, schoolId]
    );
    await db.query("UPDATE bookshare_v2.copies SET status='loaned' WHERE id=$1 AND school_id=$2", [copyId,schoolId]);
    await db.query("UPDATE bookshare_v2.reservations SET status='completed',updated_at=now() WHERE book_id=$1 AND student_id=$2 AND school_id=$3 AND status='ready'", [parent.rows[0].book_id,studentId,schoolId]);
    return loan.rows[0];
  });
}
export async function returnLoan(pool, id, condition, schoolId) {
  validUuid(schoolId);
  validUuid(id);
  if (!["normal", "damaged", "lost"].includes(condition)) throw new DomainError("Condição de devolução inválida.");
  return transact(pool, async (db) => {
    const loan = await db.query("SELECT * FROM bookshare_v2.loans WHERE id=$1 AND school_id=$2 FOR UPDATE", [id,schoolId]);
    if (!loan.rowCount) throw new DomainError("Empréstimo não encontrado.", 404);
    if (loan.rows[0].status !== "active") throw new DomainError("Este empréstimo já foi devolvido.", 409);
    const updated = await db.query(
      "UPDATE bookshare_v2.loans SET status='returned',returned_at=now(),return_condition=$2 WHERE id=$1 AND school_id=$3 RETURNING *",
      [id, condition,schoolId]
    );
    const status = condition === "normal" ? "available" : condition;
    await db.query("UPDATE bookshare_v2.copies SET status=$2 WHERE id=$1 AND school_id=$3", [loan.rows[0].copy_id, status,schoolId]);
    return updated.rows[0];
  });
}
export async function renewLoan(pool, id, dueDate, schoolId) {
  validUuid(schoolId);
  validUuid(id);
  const due = validDueDate(dueDate);
  return transact(pool, async (db) => {
    const loan = await db.query("SELECT * FROM bookshare_v2.loans WHERE id=$1 AND school_id=$2 FOR UPDATE", [id,schoolId]);
    if (!loan.rowCount) throw new DomainError("Empréstimo não encontrado.", 404);
    const old = loan.rows[0];
    if (old.status !== "active") throw new DomainError("Empréstimo já encerrado.", 409);
    if (old.renewals >= 2) throw new DomainError("Limite de duas renovações atingido.", 409);
    const oldDue = new Date(old.due_date).toISOString().slice(0,10);
    if (due <= oldDue) throw new DomainError("A nova data deve ser posterior ao vencimento atual.");
    const updated = await db.query("UPDATE bookshare_v2.loans SET due_date=$2, renewals=renewals+1 WHERE id=$1 AND school_id=$3 RETURNING *", [id, due,schoolId]);
    return updated.rows[0];
  });
}

export async function transactReservation(pool, id, nextStatus, schoolId) {
  validUuid(schoolId);
  validUuid(id);
  if(!["ready","completed","cancelled"].includes(nextStatus)) throw new DomainError("Estado de reserva inválido.");
  return transact(pool, async db => {
    const basic=await db.query("SELECT book_id FROM bookshare_v2.reservations WHERE id=$1 AND school_id=$2",[id,schoolId]);
    if(!basic.rowCount) throw new DomainError("Reserva não encontrada.",404);
    await db.query("SELECT id FROM bookshare_v2.books WHERE id=$1 AND school_id=$2 FOR UPDATE",[basic.rows[0].book_id,schoolId]);
    const reservation=await db.query("SELECT * FROM bookshare_v2.reservations WHERE id=$1 AND school_id=$2 FOR UPDATE",[id,schoolId]);
    const current=reservation.rows[0];
    if (["cancelled","completed"].includes(current.status)) throw new DomainError("Esta reserva já foi encerrada.",409);
    if (nextStatus==="ready") {
      if(current.status!=="waiting") throw new DomainError("Só reservas aguardando podem ser disponibilizadas.",409);
      const amount=await db.query("SELECT count(*)::int AS available FROM bookshare_v2.copies WHERE book_id=$1 AND school_id=$2 AND status='available'",[current.book_id,schoolId]);
      const others=await db.query("SELECT count(*)::int AS ready FROM bookshare_v2.reservations WHERE book_id=$1 AND status='ready' AND id<>$2 AND school_id=$3",[current.book_id,id,schoolId]);
      if(others.rows[0].ready >= amount.rows[0].available) throw new DomainError("Nenhum exemplar disponível para esta reserva.",409);
    }
    if(nextStatus==="completed") {
      if(current.status!=="ready") throw new DomainError("A reserva ainda não está disponível.",409);
      const loan=await db.query("SELECT 1 FROM bookshare_v2.loans l JOIN bookshare_v2.copies c ON c.id=l.copy_id WHERE l.student_id=$1 AND c.book_id=$2 AND l.status='active' AND l.school_id=$3 LIMIT 1",[current.student_id,current.book_id,schoolId]);
      if(!loan.rowCount) throw new DomainError("Registre primeiro o empréstimo ao aluno.",409);
    }
    const updated=await db.query("UPDATE bookshare_v2.reservations SET status=$2,updated_at=now() WHERE id=$1 AND school_id=$3 RETURNING *",[id,nextStatus,schoolId]);
    return updated.rows[0];
  });
}
