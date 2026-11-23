import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
test("o esquema define escolas e relacionamentos entre cadastros",()=>{
 const sql=readFileSync("schema.sql","utf8");
 assert.match(sql,/CREATE TABLE IF NOT EXISTS schools/);
 assert.match(sql,/copies_book_same_school/);
 assert.match(sql,/loans_student_same_school/);
 assert.match(sql,/students_school_registration/);
});
test("a API exige escola para operações de biblioteca",()=>{
 const flows=readFileSync("src/flows.js","utf8");
 assert.match(flows,/schoolId/);
 assert.match(flows,/loans\(student_id,copy_id,due_date,issued_by,school_id\)/);
});
