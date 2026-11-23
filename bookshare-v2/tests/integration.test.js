import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { Client } from "pg";
import sharp from "sharp";
import { chromium } from "playwright";
import { readFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";

const BASE="http://127.0.0.1:3000";
const ADMIN_EMAIL="qa.admin@bookshare.test";
const ADMIN_PASSWORD="Local_test_very_strong_2026";
const origin=BASE;
const ok=(res,status)=>assert.equal(res.status,status,`HTTP ${res.status}, esperado ${status}: ${res.body?.error||""}`);

async function request(method,path,data,cookie,withOrigin=true){
  const response=await fetch(BASE+"/api"+path,{
    method,headers:{
      ...(data!==undefined?{"Content-Type":"application/json"}:{}),
      ...(cookie?{Cookie:cookie}:{}),
      ...(withOrigin?{Origin:origin}:{}),
    },
    ...(data!==undefined?{body:JSON.stringify(data)}:{})
  });
  const body=await response.json().catch(()=>({error:"JSON inválido"}));
  return {status:response.status,body,cookie:response.headers.get("set-cookie")?.split(";")[0]||null};
}
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));

test("BookShare V2: API, banco, permissões e interface real", {timeout:240000},async t=>{
  const client=new Client({connectionString:process.env.DATABASE_URL});
  await client.connect();
  t.after(async()=>await client.end());
  await client.query(`DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;
  END $$;`);
  await client.query(readFileSync("schema.sql","utf8"));
  const env={...process.env,PORT:"3000",NODE_ENV:"test",APP_ORIGIN:BASE,
    JWT_SECRET:"integracao_apenas_teste_aleatorio_muito_longo_2026",
    BOOTSTRAP_ADMIN_NAME:"Admin QA",BOOTSTRAP_ADMIN_EMAIL:ADMIN_EMAIL,BOOTSTRAP_ADMIN_PASSWORD:ADMIN_PASSWORD};
  const server=spawn(process.execPath,["src/server.js"],{env,stdio:["ignore","pipe","pipe"]});
  let output="";
  server.stderr.on("data",buffer=>output+=buffer.toString().slice(-1000));
  server.stdout.on("data",buffer=>output+=buffer.toString().slice(-1000));
  t.after(async()=>{server.kill();await delay(200)});
  let ready=false;
  for(let i=0;i<100;i++){
    if(server.exitCode!==null)throw Error("Servidor caiu: "+output);
    try{const r=await request("GET","/health");if(r.status===200){ready=true;break;}}catch{}
    await delay(200);
  }
  assert.ok(ready,"Servidor não iniciou: "+output);
  await t.test("autenticação e origem",async()=>{
    ok(await request("GET","/me"),401);
    ok(await request("POST","/auth/login",{email:ADMIN_EMAIL,password:"incorreta"}),401);
    ok(await request("POST","/auth/login",{email:ADMIN_EMAIL,password:ADMIN_PASSWORD},null,false),403);
  });
  const login=await request("POST","/auth/login",{email:ADMIN_EMAIL,password:ADMIN_PASSWORD});
  ok(login,200);
  assert.ok(login.cookie?.startsWith("bs_v2="));
  const cookie=login.cookie;
  let student1,student2,book,copy1,copy2,loan1,reservationId;
  await t.test("cadastros e validação de dados",async()=>{
    const s1=await request("POST","/students",{name:"Estudante Alpha QA",registration:"QA-001",class_name:"3º B",contact:""},cookie);
    ok(s1,201);student1=s1.body.item.id;
    const s2=await request("POST","/students",{name:"Estudante Beta QA",registration:"QA-002",class_name:"3º A"},cookie);
    ok(s2,201);student2=s2.body.item.id;
    ok(await request("POST","/students",{name:"Estudante duplicado",registration:"QA-001",class_name:"3º B"},cookie),409);
    ok(await request("POST","/students",{name:"Sem matrícula",registration:"",class_name:"3º B"},cookie),400);
    const found=await request("GET","/students?q="+encodeURIComponent("Alpha"),undefined,cookie);
    ok(found,200);assert.ok(found.body.items.some(x=>x.id===student1));
    const b=await request("POST","/books",{title:"O livro de teste",author:"Equipe QA",category:"Literatura"},cookie);
    ok(b,201);book=b.body.item.id;
    const c1=await request("POST","/copies",{book_id:book,code:"QA-COPY-001"},cookie);
    ok(c1,201);copy1=c1.body.item.id;
    const c2=await request("POST","/copies",{book_id:book,code:"QA-COPY-002"},cookie);
    ok(c2,201);copy2=c2.body.item.id;
    ok(await request("POST","/copies",{book_id:book,code:"QA-COPY-001"},cookie),409);
  });
  await t.test("reserva garante exemplar para aluno",async()=>{
    const r=await request("POST","/reservations",{student_id:student1,book_id:book},cookie);
    ok(r,201);reservationId=r.body.item.id;
    ok(await request("POST","/reservations/"+reservationId+"/status",{status:"ready"},cookie),200);
    const due=new Date(Date.now()+15*86400000).toISOString().slice(0,10);
    ok(await request("POST","/loans",{student_id:student2,copy_id:copy1,due_date:due},cookie),409);
    const loan=await request("POST","/loans",{student_id:student1,copy_id:copy1,due_date:due},cookie);
    ok(loan,201);loan1=loan.body.item.id;
    const reservations=await request("GET","/reservations",undefined,cookie);
    ok(reservations,200);assert.equal(reservations.body.items.find(x=>x.id===reservationId).status,"completed");
    ok(await request("POST","/loans",{student_id:student2,copy_id:copy1,due_date:due},cookie),409);
  });
  await t.test("devolução realmente libera exemplar",async()=>{
    ok(await request("POST","/loans/"+loan1+"/return",{condition:"normal"},cookie),200);
    ok(await request("POST","/loans/"+loan1+"/return",{condition:"normal"},cookie),409);
    const copies=await request("GET","/copies?book_id="+book,undefined,cookie);
    ok(copies,200);assert.equal(copies.body.items.find(x=>x.id===copy1).status,"available");
  });
  await t.test("renovação, bloqueio, atrasos e exemplar danificado",async()=>{
    const due=new Date(Date.now()+15*86400000).toISOString().slice(0,10);
    const other=await request("POST","/loans",{student_id:student2,copy_id:copy1,due_date:due},cookie);
    ok(other,201);const id=other.body.item.id;
    ok(await request("POST","/loans",{student_id:student2,copy_id:copy2,due_date:"2026-02-31"},cookie),400);
    const renewed=new Date(Date.now()+30*86400000).toISOString().slice(0,10);
    const renew=await request("POST","/loans/"+id+"/renew",{due_date:renewed},cookie);
    ok(renew,200);assert.equal(renew.body.item.renewals,1);
    const renewed2=new Date(Date.now()+45*86400000).toISOString().slice(0,10);
    ok(await request("POST","/loans/"+id+"/renew",{due_date:renewed2},cookie),200);
    ok(await request("POST","/loans/"+id+"/renew",{due_date:new Date(Date.now()+60*86400000).toISOString().slice(0,10)},cookie),409);
    ok(await request("POST","/loans/"+id+"/return",{condition:"damaged"},cookie),200);
    ok(await request("POST","/loans",{student_id:student1,copy_id:copy1,due_date:due},cookie),409);
  });
  await t.test("empréstimos concorrentes não duplicam exemplar",async()=>{
    const due=new Date(Date.now()+15*86400000).toISOString().slice(0,10);
    const [a,b]=await Promise.all([
      request("POST","/loans",{student_id:student1,copy_id:copy2,due_date:due},cookie),
      request("POST","/loans",{student_id:student2,copy_id:copy2,due_date:due},cookie)
    ]);
    assert.deepEqual([a.status,b.status].sort(),[201,409]);
    const winner=a.status===201?a:b;
    ok(await request("POST","/loans/"+winner.body.item.id+"/return",{condition:"normal"},cookie),200);
  });
  await t.test("segurança, uploads e autorização por perfil",async()=>{
    const image=await sharp({create:{width:18,height:18,channels:3,background:"#3457f5"}}).png().toBuffer();
    const up=await request("POST","/media",{image:"data:image/png;base64,"+image.toString("base64")},cookie);
    ok(up,201);
    const uploaded=await fetch(BASE+"/api/media/"+up.body.id,{headers:{Cookie:cookie}});
    assert.equal(uploaded.status,200);assert.equal(uploaded.headers.get("content-type"),"image/webp");
    const studentPhoto=await request("PATCH","/students/"+student1,{name:"Estudante Alpha QA",registration:"QA-001",class_name:"3º B",contact:"",photo_id:up.body.id},cookie);
    ok(studentPhoto,200);assert.equal(studentPhoto.body.item.photo_id,up.body.id);
    const bookCover=await request("PATCH","/books/"+book,{title:"O livro de teste",author:"Equipe QA",isbn:"",category:"Literatura",cover_id:up.body.id},cookie);
    ok(bookCover,200);assert.equal(bookCover.body.item.cover_id,up.body.id);
    ok(await request("POST","/media",{image:"data:text/html;base64,PGh0bWw+"},cookie),400);
    ok(await request("POST","/books",{title:"Origem inválida",author:"QA"},cookie,false),403);
    const staff=await request("POST","/users",{name:"Funcionária QA",email:"staff.qa@bookshare.test",role:"librarian",password:"StaffStrong2026!"},cookie);
    ok(staff,201);
    const staffLogin=await request("POST","/auth/login",{email:"staff.qa@bookshare.test",password:"StaffStrong2026!"});
    ok(staffLogin,200);
    ok(await request("GET","/users",undefined,staffLogin.cookie),403);
    ok(await request("GET","/dashboard",undefined,staffLogin.cookie),200);
  });
  await t.test("dashboard traz dados persistidos",async()=>{
    const dash=await request("GET","/dashboard",undefined,cookie);
    ok(dash,200);
    assert.ok(dash.body.metrics.students>=2);
    assert.ok(dash.body.metrics.books>=1);
    assert.ok(dash.body.metrics.available>=1);
  });
  await t.test("navegador desktop e mobile acessa páginas e formulários",async()=>{
    mkdirSync("artifacts",{recursive:true});
    const browser=await chromium.launch({headless:true});
    t.after(async()=>await browser.close());
    const page=await browser.newPage({viewport:{width:1366,height:820},deviceScaleFactor:1});
    const errors=[];page.on("pageerror",err=>errors.push(err.message));
    await page.goto(BASE,{waitUntil:"networkidle"});
    assert.equal(await page.title(),"BookShare — Biblioteca escolar");
    await page.screenshot({path:"artifacts/v2-login-desktop.png",fullPage:true});
    await page.locator("#login-form [name=email]").fill(ADMIN_EMAIL);
    await page.locator("#login-form [name=password]").fill(ADMIN_PASSWORD);
    await page.locator("#login-form button[type=submit]").click();
    await page.locator("#workspace:not([hidden])").waitFor();
    await page.screenshot({path:"artifacts/v2-dashboard-desktop.png",fullPage:true});
    await page.locator('[data-route="students"]').click();
    await page.locator('[data-modal="student"]').click();
    await page.locator('#modal-form [name=name]').fill("Aluno criado na interface");
    await page.locator('#modal-form [name=registration]').fill("QA-UI-001");
    await page.locator('#modal-form [name=class_name]').fill("1º C");
    await page.locator('#modal-form button[type=submit]').click();
    await page.getByText("Aluno criado na interface",{exact:true}).waitFor();
    await page.screenshot({path:"artifacts/v2-alunos-desktop.png",fullPage:true});
    await page.locator('[data-route="loans"]').click();
    await page.locator('[data-modal="loan"]').click();
    await page.locator('#modal-form [name=student_id]').selectOption(student1);
    await page.locator('#modal-form [name=copy_id]').selectOption(copy2);
    await page.locator('#modal-form button[type=submit]').click();
    await page.locator('[data-loan-filter="active"]').click();
    await page.locator('[data-page="loans"] tbody tr').first().waitFor();
    await page.screenshot({path:"artifacts/v2-emprestimos-desktop.png",fullPage:true});
    await page.locator('[data-page="loans"] [data-return]').first().click();
    await page.locator('#modal-form [name=condition]').selectOption("normal");
    await page.locator('#modal-form button[type=submit]').click();
    await page.getByText("Operação concluída.",{exact:true}).waitFor();
    assert.deepEqual(errors,[]);
    const mobile=await browser.newPage({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
    mobile.on("pageerror",err=>errors.push(err.message));
    await mobile.goto(BASE,{waitUntil:"networkidle"});
    await mobile.screenshot({path:"artifacts/v2-login-mobile.png",fullPage:true});
    await mobile.locator("#login-form [name=email]").fill(ADMIN_EMAIL);
    await mobile.locator("#login-form [name=password]").fill(ADMIN_PASSWORD);
    await mobile.locator("#login-form button[type=submit]").click();
    await mobile.locator("#workspace:not([hidden])").waitFor();
    await mobile.locator("#menu-toggle").click();
    await mobile.locator('[data-route="books"]').click();
    await mobile.locator('[data-page="books"]:not([hidden])').waitFor();
    await mobile.locator(".book-card").first().waitFor();
    const noHeaderCollision=await mobile.evaluate(()=>{
      const brand=document.querySelector(".top-brand").getBoundingClientRect();
      const logout=document.querySelector(".top-right .text-button").getBoundingClientRect();
      const menu=document.querySelector(".mobile-menu").getBoundingClientRect();
      return brand.right+3<=logout.left && logout.right+3<=menu.left;
    });
    assert.ok(noHeaderCollision,"Cabeçalho mobile tem elementos sobrepostos");
    await mobile.screenshot({path:"artifacts/v2-acervo-mobile.png",fullPage:true});
    assert.deepEqual(errors,[]);
  });
});
