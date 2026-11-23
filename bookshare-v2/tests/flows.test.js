import test from "node:test";
import assert from "node:assert/strict";
import { DomainError, requiredText, validUuid, validDueDate, returnLoan, createLoan } from "../src/flows.js";
test("campos obrigatórios recusam vazios", () => {
  assert.throws(() => requiredText("  ", "Nome"), DomainError);
  assert.equal(requiredText(" Aluna ", "Nome"), "Aluna");
});
test("IDs inválidos são recusados", () => assert.throws(() => validUuid("x"), DomainError));
test("data no passado é recusada", () => assert.throws(() => validDueDate("2020-01-01", new Date("2026-11-23T12:00:00Z")), DomainError));
test("condição inválida de devolução é recusada antes de acessar DB", async () => {
  await assert.rejects(() => returnLoan(null, "00000000-0000-4000-8000-000000000001", "unknown"), DomainError);
});
test("IDs inválidos nunca iniciam transação", async () => {
  await assert.rejects(() => createLoan(null, { studentId:"invalid", copyId:"invalid", dueDate:"2027-01-01", userId:"invalid" }), DomainError);
});
