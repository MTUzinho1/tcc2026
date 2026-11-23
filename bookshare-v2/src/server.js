import "dotenv/config";
import express from "express";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import jwt from "jsonwebtoken";
import bcrypt from "bcryptjs";
import sharp from "sharp";
import { Pool } from "pg";
import { fileURLToPath } from "node:url";
import { join, dirname } from "node:path";
import { DomainError, requiredText, optionalText, validUuid, createLoan, returnLoan, renewLoan, transactReservation } from "./flows.js";

const app = express();
const PORT = Number(process.env.PORT || 3000);
const secret = String(process.env.JWT_SECRET || "");
if (secret.length < 32) throw new Error("Configure JWT_SECRET com pelo menos 32 caracteres.");
if (!process.env.DATABASE_URL) throw new Error("Configure DATABASE_URL de um banco NOVO da V2.");
const pool = new Pool({connectionString:process.env.DATABASE_URL, ssl:process.env.DATABASE_SSL === "true" ? {rejectUnauthorized:true}:false});
const root = join(dirname(fileURLToPath(import.meta.url)), "..", "public");
app.disable("x-powered-by");
app.use(helmet({contentSecurityPolicy:{directives:{"default-src":["'self'"],"script-src":["'self'"],"style-src":["'self'"],"img-src":["'self'","data:","https://books.google.com","https://books.googleusercontent.com","https://covers.openlibrary.org","https://images-na.ssl-images-amazon.com","https://m.media-amazon.com"],"connect-src":["'self'"],"object-src":["'none'"],"frame-ancestors":["'none'"]}}}));
app.use(express.json({limit:"2mb"}));
app.use(express.static(root,{index:false}));
app.use("/api",rateLimit({windowMs:15*60*1000,limit:300,standardHeaders:"draft-7",legacyHeaders:false}));
app.use("/api/auth/login",rateLimit({windowMs:15*60*1000,limit:12,standardHeaders:"draft-7",legacyHeaders:false}));

function cookies(req) {
  const raw = String(req.headers.cookie || "");
  return Object.fromEntries(raw.split(";").map(x=>{let pos=x.indexOf("=");return pos < 0 ? ["",""] : [x.slice(0,pos).trim(),x.slice(pos+1).trim()]}));
}
async function authenticate(req,res,next){
  try {
    const token = cookies(req).bs_v2;
    if(!token) throw new DomainError("Faça login para continuar.",401);
    let claims;
    try { claims=jwt.verify(token,secret,{algorithms:["HS256"]}); }
    catch { throw new DomainError("Sessão inválida ou expirada. Entre novamente.",401); }
    const users=await pool.query("SELECT id,name,role,active FROM bookshare_v2.users WHERE id=$1",[claims.sub]);
    if(!users.rowCount || !users.rows[0].active) throw new DomainError("Conta desativada ou sessão encerrada.",401);
    req.identity={sub:users.rows[0].id,name:users.rows[0].name,role:users.rows[0].role};
    next();
  }catch(e){ next(e); }
}
function admin(req,res,next){if(req.identity.role!=="admin")return next(new DomainError("Acesso restrito ao administrador.",403));next()}
function guardOrigin(req,res,next){
  if(["GET","HEAD","OPTIONS"].includes(req.method))return next();
  const origin=req.headers.origin;
  const expected=process.env.APP_ORIGIN;
  if (!origin || !expected || origin !== expected) return next(new DomainError("Origem não autorizada. Configure APP_ORIGIN com o endereço exato do sistema.",403));
  next();
}
app.use("/api",guardOrigin);
const wrap = f => (req,res,next)=>Promise.resolve(f(req,res)).catch(next);
function payload(req){ return req.body && typeof req.body==="object" && !Array.isArray(req.body) ? req.body:{}; }
function numberLimit(value, max=1000) { const n = Number(value || 40);return Number.isInteger(n)?Math.min(Math.max(n,1),max):40; }
async function query(sql,args=[]){const r=await pool.query(sql,args);return r.rows}
async function bootAdmin(){
  const email=String(process.env.BOOTSTRAP_ADMIN_EMAIL||"").trim().toLowerCase();
  const password=String(process.env.BOOTSTRAP_ADMIN_PASSWORD||"");
  if(!email || !password) return;
  if(password.length<12)throw new Error("BOOTSTRAP_ADMIN_PASSWORD precisa ter pelo menos 12 caracteres.");
  const count=await pool.query("SELECT count(*)::int AS total FROM bookshare_v2.users");
  if(count.rows[0].total>0)return;
  const hash=await bcrypt.hash(password,12);
  await pool.query("INSERT INTO bookshare_v2.users(name,email,password_hash,role) VALUES($1,$2,$3,'admin') ON CONFLICT(email) DO NOTHING",
    [requiredText(process.env.BOOTSTRAP_ADMIN_NAME||"Administrador","Nome"),email,hash]);
}
app.get("/",(req,res)=>res.sendFile(join(root,"index.html")));
app.get("/api/health",wrap(async(req,res)=>{await pool.query("SELECT 1");res.json({ok:true,app:"BookShare V2"})}));
app.post("/api/auth/login",wrap(async(req,res)=>{
  const b=payload(req);
  const email=String(b.email||"").trim().toLowerCase(), password=String(b.password||"");
  const result=await query("SELECT id,name,email,role,password_hash FROM bookshare_v2.users WHERE email=$1 AND active=true",[email]);
  const user=result[0];
  if(!user || !(await bcrypt.compare(password,user.password_hash)))throw new DomainError("E-mail ou senha inválidos.",401);
  const token=jwt.sign({sub:user.id,name:user.name,role:user.role},secret,{expiresIn:"8h",algorithm:"HS256"});
  res.cookie("bs_v2",token,{httpOnly:true,secure:process.env.NODE_ENV==="production",sameSite:"strict",path:"/",maxAge:8*60*60*1000});
  res.json({user:{id:user.id,name:user.name,role:user.role,email:user.email}});
}));
app.post("/api/auth/logout",(req,res)=>{res.clearCookie("bs_v2",{httpOnly:true,secure:process.env.NODE_ENV==="production",sameSite:"strict",path:"/"});res.json({ok:true})});
app.get("/api/me",authenticate,wrap(async(req,res)=>{
  const users=await query("SELECT id,name,email,role FROM bookshare_v2.users WHERE id=$1 AND active=true",[req.identity.sub]);
  if(!users.length)throw new DomainError("Conta desativada.",401);
  res.json({user:users[0]});
}));
app.use("/api",authenticate);
app.post("/api/me/password",wrap(async(req,res)=>{
  const body=payload(req),current=String(body.current_password||""),updated=String(body.new_password||"");
  if(updated.length<12 || updated.length>128) throw new DomainError("A nova senha deve ter entre 12 e 128 caracteres.");
  if(updated===current) throw new DomainError("A nova senha deve ser diferente da anterior.");
  const found=await query("SELECT password_hash FROM bookshare_v2.users WHERE id=$1",[req.identity.sub]);
  if(!found.length || !(await bcrypt.compare(current,found[0].password_hash))) throw new DomainError("Senha atual incorreta.",403);
  const hash=await bcrypt.hash(updated,12);
  await query("UPDATE bookshare_v2.users SET password_hash=$2 WHERE id=$1",[req.identity.sub,hash]);
  res.json({ok:true,message:"Senha atualizada."});
}));
app.get("/api/dashboard",wrap(async(req,res)=>{
  const [metrics,attention,recent]=await Promise.all([
    query(`SELECT
      (SELECT count(*)::int FROM bookshare_v2.students WHERE active=true) students,
      (SELECT count(*)::int FROM bookshare_v2.books) books,
      (SELECT count(*)::int FROM bookshare_v2.copies WHERE status='available') available,
      (SELECT count(*)::int FROM bookshare_v2.loans WHERE status='active') active_loans,
      (SELECT count(*)::int FROM bookshare_v2.loans WHERE status='active' AND due_date<CURRENT_DATE) overdue,
      (SELECT count(*)::int FROM bookshare_v2.reservations WHERE status='waiting') reservations`),
    query(`SELECT l.id,s.name student,b.title book,l.due_date,c.code FROM bookshare_v2.loans l JOIN bookshare_v2.students s ON s.id=l.student_id JOIN bookshare_v2.copies c ON c.id=l.copy_id JOIN bookshare_v2.books b ON b.id=c.book_id WHERE l.status='active' AND l.due_date<=CURRENT_DATE+INTERVAL '3 days' ORDER BY l.due_date ASC LIMIT 8`),
    query(`SELECT l.id,s.name student,b.title book,l.due_date,l.loaned_at,l.returned_at,l.status FROM bookshare_v2.loans l JOIN bookshare_v2.students s ON s.id=l.student_id JOIN bookshare_v2.copies c ON c.id=l.copy_id JOIN bookshare_v2.books b ON b.id=c.book_id ORDER BY l.loaned_at DESC LIMIT 8`)
  ]);
  res.json({metrics:metrics[0],attention,recent});
}));
app.get("/api/students",wrap(async(req,res)=>{
  const term=String(req.query.q||"").slice(0,100);
  const rows=await query("SELECT id,name,registration,class_name,contact,photo_id,active,created_at FROM bookshare_v2.students WHERE ($1='' OR name ILIKE '%'||$1||'%' OR registration ILIKE '%'||$1||'%') ORDER BY name LIMIT $2",[term,numberLimit(req.query.limit)]);
  res.json({items:rows});
}));
app.post("/api/students",wrap(async(req,res)=>{
  const b=payload(req);
  const rows=await query("INSERT INTO bookshare_v2.students(name,registration,class_name,contact,photo_id) VALUES($1,$2,$3,$4,$5) RETURNING id,name,registration,class_name,contact,photo_id,active",
    [requiredText(b.name,"Nome"),requiredText(b.registration,"Matrícula",60),requiredText(b.class_name,"Turma",80),optionalText(b.contact,120),b.photo_id?validUuid(b.photo_id):null]);
  res.status(201).json({item:rows[0]});
}));
app.patch("/api/students/:id",wrap(async(req,res)=>{
 const b=payload(req),id=validUuid(req.params.id);
 const rows=await query("UPDATE bookshare_v2.students SET name=$2,registration=$3,class_name=$4,contact=$5,active=$6,photo_id=$7 WHERE id=$1 RETURNING id,name,registration,class_name,contact,active,photo_id",
 [id,requiredText(b.name,"Nome"),requiredText(b.registration,"Matrícula",60),requiredText(b.class_name,"Turma",80),optionalText(b.contact,120),b.active!==false,b.photo_id?validUuid(b.photo_id):null]);
 if(!rows.length)throw new DomainError("Aluno não encontrado.",404);res.json({item:rows[0]});
}));
app.get("/api/books",wrap(async(req,res)=>{
 const term=String(req.query.q||"").slice(0,100);
 const rows=await query(`SELECT b.id,b.title,b.author,b.isbn,b.category,b.cover_id,b.cover_url,
 count(c.id)::int copies,count(c.id) FILTER(WHERE c.status='available')::int available
 FROM bookshare_v2.books b LEFT JOIN bookshare_v2.copies c ON c.book_id=b.id
 WHERE ($1='' OR b.title ILIKE '%'||$1||'%' OR b.author ILIKE '%'||$1||'%' OR COALESCE(b.isbn,'') ILIKE '%'||$1||'%')
 GROUP BY b.id ORDER BY b.title LIMIT $2`,[term,numberLimit(req.query.limit)]);
 res.json({items:rows});
}));
app.post("/api/books",wrap(async(req,res)=>{
 const b=payload(req);
 const rows=await query("INSERT INTO bookshare_v2.books(title,author,isbn,category,cover_id) VALUES($1,$2,$3,$4,$5) RETURNING *",
 [requiredText(b.title,"Título",180),requiredText(b.author,"Autor"),optionalText(b.isbn,20)||null,optionalText(b.category,80)||"Geral",b.cover_id?validUuid(b.cover_id):null]);
 res.status(201).json({item:rows[0]});
}));
app.patch("/api/books/:id",wrap(async(req,res)=>{
 const b=payload(req),id=validUuid(req.params.id);
 const rows=await query("UPDATE bookshare_v2.books SET title=$2,author=$3,isbn=$4,category=$5,cover_id=$6 WHERE id=$1 RETURNING *",
 [id,requiredText(b.title,"Título",180),requiredText(b.author,"Autor"),optionalText(b.isbn,20)||null,optionalText(b.category,80)||"Geral",b.cover_id?validUuid(b.cover_id):null]);
 if(!rows.length)throw new DomainError("Livro não encontrado.",404);res.json({item:rows[0]});
}));
app.get("/api/copies",wrap(async(req,res)=>{
 let id=req.query.book_id; if(id)validUuid(id);
 const rows=await query("SELECT c.id,c.code,c.status,c.book_id,b.title FROM bookshare_v2.copies c JOIN bookshare_v2.books b ON b.id=c.book_id WHERE ($1::uuid IS NULL OR c.book_id=$1) ORDER BY b.title,c.code LIMIT $2",[id||null,numberLimit(req.query.limit,200)]);
 res.json({items:rows});
}));
app.post("/api/copies",wrap(async(req,res)=>{
 const b=payload(req),rows=await query("INSERT INTO bookshare_v2.copies(book_id,code) VALUES($1,$2) RETURNING *",[validUuid(b.book_id),requiredText(b.code,"Código do exemplar",60)]);
 res.status(201).json({item:rows[0]});
}));
app.get("/api/loans",wrap(async(req,res)=>{
 let status=String(req.query.status||"active");
 if(!["active","returned","all"].includes(status))status="active";
 const rows=await query(`SELECT l.id,l.student_id,l.copy_id,l.status,l.loaned_at,l.due_date,l.returned_at,l.return_condition,l.renewals,
 s.name student,c.code,b.title book FROM bookshare_v2.loans l JOIN bookshare_v2.students s ON s.id=l.student_id JOIN bookshare_v2.copies c ON c.id=l.copy_id JOIN bookshare_v2.books b ON b.id=c.book_id
 WHERE ($1='all' OR l.status=$1) ORDER BY CASE WHEN l.status='active' THEN 0 ELSE 1 END,l.due_date ASC LIMIT $2`,[status,numberLimit(req.query.limit,200)]);
 res.json({items:rows});
}));
app.post("/api/loans",wrap(async(req,res)=>{
 const b=payload(req);
 const loan=await createLoan(pool,{studentId:b.student_id,copyId:b.copy_id,dueDate:b.due_date,userId:req.identity.sub});
 res.status(201).json({item:loan});
}));
app.post("/api/loans/:id/return",wrap(async(req,res)=>{
 const loan=await returnLoan(pool,req.params.id,String(payload(req).condition||"normal"));
 res.json({item:loan});
}));
app.post("/api/loans/:id/renew",wrap(async(req,res)=>{
 const loan=await renewLoan(pool,req.params.id,payload(req).due_date);
 res.json({item:loan});
}));
app.get("/api/reservations",wrap(async(req,res)=>{
 const rows=await query(`SELECT r.id,r.status,r.created_at,r.student_id,r.book_id,s.name student,b.title book FROM bookshare_v2.reservations r
 JOIN bookshare_v2.students s ON s.id=r.student_id JOIN bookshare_v2.books b ON b.id=r.book_id
 ORDER BY CASE WHEN r.status IN ('waiting','ready') THEN 0 ELSE 1 END,r.created_at DESC LIMIT $1`,[numberLimit(req.query.limit)]);
 res.json({items:rows});
}));
app.post("/api/reservations",wrap(async(req,res)=>{
 const b=payload(req),student=validUuid(b.student_id),book=validUuid(b.book_id);
 const active=await query("SELECT id FROM bookshare_v2.students WHERE id=$1 AND active=true",[student]);
 if(!active.length)throw new DomainError("Aluno não encontrado ou inativo.",404);
 const rows=await query("INSERT INTO bookshare_v2.reservations(student_id,book_id,created_by) VALUES($1,$2,$3) RETURNING *",[student,book,req.identity.sub]);
 res.status(201).json({item:rows[0]});
}));
app.post("/api/reservations/:id/status",wrap(async(req,res)=>{
 const b=payload(req),status=String(b.status||"");
 if(!["ready","completed","cancelled"].includes(status))throw new DomainError("Transição de reserva inválida.");
 const id=validUuid(req.params.id);
 const item=await transactReservation(pool,id,status);
 res.json({item});
}));
app.get("/api/users",admin,wrap(async(req,res)=>{
 res.json({items:await query("SELECT id,name,email,role,active,created_at FROM bookshare_v2.users ORDER BY name LIMIT 100")});
}));
app.post("/api/users",admin,wrap(async(req,res)=>{
 const b=payload(req),password=String(b.password||"");
 if(password.length<12)throw new DomainError("A senha precisa ter pelo menos 12 caracteres.");
 if(!["admin","librarian"].includes(b.role))throw new DomainError("Perfil inválido.");
 const hash=await bcrypt.hash(password,12);
 const rows=await query("INSERT INTO bookshare_v2.users(name,email,password_hash,role) VALUES($1,$2,$3,$4) RETURNING id,name,email,role,active",
 [requiredText(b.name,"Nome"),requiredText(b.email,"E-mail",180).toLowerCase(),hash,b.role]);
 res.status(201).json({item:rows[0]});
}));
app.post("/api/media",wrap(async(req,res)=>{
 const value=String(payload(req).image||"");
 const match=value.match(/^data:image\/(?:png|jpeg|webp);base64,([A-Za-z0-9+/=]+)$/);
 if(!match || value.length>1800000)throw new DomainError("Envie uma imagem PNG, JPG ou WebP de até 1,3 MB.");
 const raw=Buffer.from(match[1],"base64");
 let buffer;
 try{buffer=await sharp(raw,{limitInputPixels:16000000}).rotate().resize({width:700,height:700,fit:"inside",withoutEnlargement:true}).webp({quality:78}).toBuffer()}
 catch{throw new DomainError("Arquivo de imagem inválido.");}
 const rows=await query("INSERT INTO bookshare_v2.media_assets(mime,data,created_by) VALUES('image/webp',$1,$2) RETURNING id",[buffer,req.identity.sub]);
 res.status(201).json({id:rows[0].id,url:"/api/media/"+rows[0].id});
}));
app.get("/api/media/:id",wrap(async(req,res)=>{
 const rows=await query("SELECT mime,data FROM bookshare_v2.media_assets WHERE id=$1",[validUuid(req.params.id)]);
 if(!rows.length)throw new DomainError("Imagem não encontrada.",404);
 res.set({"Content-Type":rows[0].mime,"Cache-Control":"private,max-age=3600","X-Content-Type-Options":"nosniff"});
 res.send(rows[0].data);
}));
app.use("/api",(req,res)=>res.status(404).json({error:"Rota não encontrada."}));
app.use((err,req,res,next)=>{
 const status=err.status || (err.code==="23505"?409:err.code==="23503"?409:500);
 if(status>=500)console.error(err);
 const message=status===500?"Erro interno. Tente novamente.":err.code==="23505"?"Já existe um cadastro com esse identificador.":err.code==="23503"?"Registro relacionado não encontrado ou em uso.":err.message;
 if(res.headersSent)return next(err);
 res.status(status).json({error:message});
});
await pool.query("SELECT 1");
await bootAdmin();
app.listen(PORT,()=>console.log("BookShare V2 rodando na porta "+PORT));
