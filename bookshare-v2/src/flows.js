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
  if (!/^\d{4}-\d{2}-\d{2}$/.test(due) || Number.isNaN(Date.parse(due + "T12:00:00Z"))) {
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
export async function createLoan(pool, { studentId, copyId, dueDate, userId }) {
  validUuid(studentId); validUuid(copyId);
  const due = validDueDate(dueDate);
  return transact(pool, async (db) => {
    const student = await db.query("SELECT active FROM students WHERE id=$1", [studentId]);
    if (!student.rowCount || !student.rows[0].active) throw new DomainError("Aluno não encontrado ou inativo.", 404);
    const copy = await db.query("SELECT status FROM copies WHERE id=$1 FOR UPDATE", [copyId]);
    if (!copy.rowCount) throw new DomainError("Exemplar não encontrado.", 404);
    if (copy.rows[0].status !== "available") throw new DomainError("Exemplar indisponível para empréstimo.", 409);
    const loan = await db.query(
      "INSERT INTO loans(student_id,copy_id,due_date,issued_by) VALUES($1,$2,$3,$4) RETURNING *",
      [studentId, copyId, due, userId]
    );
    await db.query("UPDATE copies SET status='loaned' WHERE id=$1", [copyId]);
    return loan.rows[0];
  });
}
export async function returnLoan(pool, id, condition) {
  validUuid(id);
  if (!["normal", "damaged", "lost"].includes(condition)) throw new DomainError("Condição de devolução inválida.");
  return transact(pool, async (db) => {
    const loan = await db.query("SELECT * FROM loans WHERE id=$1 FOR UPDATE", [id]);
    if (!loan.rowCount) throw new DomainError("Empréstimo não encontrado.", 404);
    if (loan.rows[0].status !== "active") throw new DomainError("Este empréstimo já foi devolvido.", 409);
    const updated = await db.query(
      "UPDATE loans SET status='returned',returned_at=now(),return_condition=$2 WHERE id=$1 RETURNING *",
      [id, condition]
    );
    const status = condition === "normal" ? "available" : condition;
    await db.query("UPDATE copies SET status=$2 WHERE id=$1", [loan.rows[0].copy_id, status]);
    return updated.rows[0];
  });
}
export async function renewLoan(pool, id, dueDate) {
  validUuid(id);
  const due = validDueDate(dueDate);
  return transact(pool, async (db) => {
    const loan = await db.query("SELECT * FROM loans WHERE id=$1 FOR UPDATE", [id]);
    if (!loan.rowCount) throw new DomainError("Empréstimo não encontrado.", 404);
    const old = loan.rows[0];
    if (old.status !== "active") throw new DomainError("Empréstimo já encerrado.", 409);
    if (old.renewals >= 2) throw new DomainError("Limite de duas renovações atingido.", 409);
    const oldDue = new Date(old.due_date).toISOString().slice(0,10);
    if (due <= oldDue) throw new DomainError("A nova data deve ser posterior ao vencimento atual.");
    const updated = await db.query("UPDATE loans SET due_date=$2, renewals=renewals+1 WHERE id=$1 RETURNING *", [id, due]);
    return updated.rows[0];
  });
}
