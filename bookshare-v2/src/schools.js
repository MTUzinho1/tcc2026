import { DomainError, requiredText, optionalText, validUuid, transact } from "./flows.js";

const wrap = fn => (req,res,next)=>Promise.resolve(fn(req,res)).catch(next);
const admin = (req,res,next)=>req.identity.role==="admin"?next():next(new DomainError("Acesso restrito ao administrador.",403));
function details(value){
 const b=value||{};
 const state=requiredText(b.state||"PR","Estado",2).toUpperCase();
 if(!/^[A-Z]{2}$/.test(state))throw new DomainError("Estado inválido.");
 return [requiredText(b.name,"Escola",160),requiredText(b.city,"Cidade",100),state,
  optionalText(b.address,220),optionalText(b.phone,40),optionalText(b.email,180)];
}
export function registerSchools(app,{pool,query}){
 app.get("/api/schools",wrap(async(req,res)=>{
  const rows=await query("SELECT s.*, (SELECT count(*)::int FROM bookshare_v2.users u WHERE u.school_id=s.id) users, (SELECT count(*)::int FROM bookshare_v2.students st WHERE st.school_id=s.id) students, (SELECT count(*)::int FROM bookshare_v2.books b WHERE b.school_id=s.id) books, (SELECT count(*)::int FROM bookshare_v2.loans l WHERE l.school_id=s.id) loans FROM bookshare_v2.schools s WHERE ($1::uuid IS NULL OR s.id=$1) ORDER BY s.active DESC,s.name",[req.identity.role==="admin"?null:req.identity.school_id]);
  res.json({items:rows});
 }));
 app.post("/api/schools",admin,wrap(async(req,res)=>{
  const args=details(req.body);
  const rows=await query("INSERT INTO bookshare_v2.schools(name,city,state,address,phone,email) VALUES($1,$2,$3,$4,$5,$6) RETURNING *",args);
  res.status(201).json({item:rows[0]});
 }));
 app.patch("/api/schools/:id",admin,wrap(async(req,res)=>{
  const id=validUuid(req.params.id),args=details(req.body);
  if(typeof req.body?.active!=="boolean")throw new DomainError("Informe a situação da escola.");
  const rows=await query("UPDATE bookshare_v2.schools SET name=$2,city=$3,state=$4,address=$5,phone=$6,email=$7,active=$8 WHERE id=$1 RETURNING *",[id,...args,req.body.active]);
  if(!rows.length)throw new DomainError("Escola não encontrada.",404);
  res.json({item:rows[0]});
 }));
 app.delete("/api/schools/:id",admin,wrap(async(req,res)=>{
  const id=validUuid(req.params.id);
  await transact(pool,async db=>{
   await db.query("SELECT pg_advisory_xact_lock(2026001,3)");
   const school=await db.query("SELECT id,active FROM bookshare_v2.schools WHERE id=$1 FOR UPDATE",[id]);
   if(!school.rowCount)throw new DomainError("Escola não encontrada.",404);
   const n=await db.query("SELECT (SELECT count(*)::int FROM bookshare_v2.users WHERE school_id=$1) users,(SELECT count(*)::int FROM bookshare_v2.students WHERE school_id=$1) students,(SELECT count(*)::int FROM bookshare_v2.books WHERE school_id=$1) books,(SELECT count(*)::int FROM bookshare_v2.loans WHERE school_id=$1) loans,(SELECT count(*)::int FROM bookshare_v2.reservations WHERE school_id=$1) reservations,(SELECT count(*)::int FROM bookshare_v2.media_assets WHERE school_id=$1) images",[id]);
   if(Object.values(n.rows[0]).some(x=>x>0))throw new DomainError("Escola possui dados vinculados. Desative-a para preservar os históricos.",409);
   const active=await db.query("SELECT count(*)::int total FROM bookshare_v2.schools WHERE active=true");
   if(school.rows[0].active&&active.rows[0].total<=1)throw new DomainError("Não é possível excluir a única escola ativa.",409);
   await db.query("DELETE FROM bookshare_v2.schools WHERE id=$1",[id]);
  });
  res.json({ok:true});
 }));
 app.delete("/api/users/:id",admin,wrap(async(req,res)=>{
  const id=validUuid(req.params.id);
  if(id===req.identity.sub)throw new DomainError("Não é permitido excluir sua própria conta.",409);
  await transact(pool,async db=>{
   await db.query("SELECT pg_advisory_xact_lock(2026001,1)");
   const user=await db.query("SELECT role,active FROM bookshare_v2.users WHERE id=$1 AND school_id=$2 FOR UPDATE",[id,req.schoolId]);
   if(!user.rowCount)throw new DomainError("Funcionário não encontrado.",404);
   if(user.rows[0].active&&user.rows[0].role==="admin"){
    const total=await db.query("SELECT count(*)::int total FROM bookshare_v2.users WHERE role='admin' AND active=true");
    if(total.rows[0].total<=1)throw new DomainError("Não é possível excluir o último administrador.",409);
   }
   const histories=await db.query("SELECT (SELECT count(*)::int FROM bookshare_v2.loans WHERE issued_by=$1) loans,(SELECT count(*)::int FROM bookshare_v2.reservations WHERE created_by=$1) reservations",[id]);
   if(histories.rows[0].loans||histories.rows[0].reservations)throw new DomainError("Funcionário tem histórico registrado. Desative o acesso em vez de excluir.",409);
   await db.query("UPDATE bookshare_v2.media_assets SET created_by=NULL WHERE created_by=$1",[id]);
   await db.query("DELETE FROM bookshare_v2.users WHERE id=$1",[id]);
  });
  res.json({ok:true});
 }));
 app.delete("/api/students/:id",admin,wrap(async(req,res)=>{
  const id=validUuid(req.params.id);
  await transact(pool,async db=>{
   const row=await db.query("SELECT id FROM bookshare_v2.students WHERE id=$1 AND school_id=$2 FOR UPDATE",[id,req.schoolId]);
   if(!row.rowCount)throw new DomainError("Aluno não encontrado.",404);
   const histories=await db.query("SELECT (SELECT count(*)::int FROM bookshare_v2.loans WHERE student_id=$1) loans,(SELECT count(*)::int FROM bookshare_v2.reservations WHERE student_id=$1) reservations",[id]);
   if(histories.rows[0].loans||histories.rows[0].reservations)throw new DomainError("Aluno possui histórico. Desative o cadastro para preservar os registros.",409);
   await db.query("DELETE FROM bookshare_v2.students WHERE id=$1",[id]);
  });res.json({ok:true});
 }));
 app.delete("/api/books/:id",admin,wrap(async(req,res)=>{
  const id=validUuid(req.params.id);
  await transact(pool,async db=>{
   const row=await db.query("SELECT id FROM bookshare_v2.books WHERE id=$1 AND school_id=$2 FOR UPDATE",[id,req.schoolId]);
   if(!row.rowCount)throw new DomainError("Livro não encontrado.",404);
   const histories=await db.query("SELECT (SELECT count(*)::int FROM bookshare_v2.reservations WHERE book_id=$1) reservations,(SELECT count(*)::int FROM bookshare_v2.loans l JOIN bookshare_v2.copies c ON c.id=l.copy_id WHERE c.book_id=$1) loans",[id]);
   if(histories.rows[0].loans||histories.rows[0].reservations)throw new DomainError("Livro possui histórico de empréstimos ou reservas e não pode ser excluído.",409);
   await db.query("DELETE FROM bookshare_v2.copies WHERE book_id=$1 AND school_id=$2",[id,req.schoolId]);
   await db.query("DELETE FROM bookshare_v2.books WHERE id=$1 AND school_id=$2",[id,req.schoolId]);
  });res.json({ok:true});
 }));
 app.delete("/api/copies/:id",admin,wrap(async(req,res)=>{
  const id=validUuid(req.params.id);
  await transact(pool,async db=>{
   const row=await db.query("SELECT id FROM bookshare_v2.copies WHERE id=$1 AND school_id=$2 FOR UPDATE",[id,req.schoolId]);
   if(!row.rowCount)throw new DomainError("Exemplar não encontrado.",404);
   const histories=await db.query("SELECT 1 FROM bookshare_v2.loans WHERE copy_id=$1 LIMIT 1",[id]);
   if(histories.rowCount)throw new DomainError("Exemplar possui histórico e não pode ser excluído.",409);
   await db.query("DELETE FROM bookshare_v2.copies WHERE id=$1 AND school_id=$2",[id,req.schoolId]);
  });res.json({ok:true});
 }));
}
