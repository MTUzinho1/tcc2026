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

async function request(method,path,data,cookie,withOrigin=true,schoolId=null){
  const response=await fetch(BASE+"/api"+path,{
    method,headers:{
      ...(data!==undefined?{"Content-Type":"application/json"}:{}),
      ...(cookie?{Cookie:cookie}:{}),
       ...(schoolId?{"x-school-id":schoolId}:{}),
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
  await t.test("administrador pode gerenciar equipe, perfil e exemplares",async()=>{
    const users=await request("GET","/users",undefined,cookie);ok(users,200);
    const employee=users.body.items.find(x=>x.email==="staff.qa@bookshare.test");
    const administrator=users.body.items.find(x=>x.email===ADMIN_EMAIL);
    assert.ok(employee?.id);
    assert.ok(administrator?.id);
    ok(await request("PATCH","/users/"+administrator.id,{name:"Admin QA",email:ADMIN_EMAIL,role:"admin",active:false},cookie),409);
    const modified=await request("PATCH","/users/"+employee.id,{name:"Bibliotecária de testes",email:employee.email,role:"librarian",active:false},cookie);
    ok(modified,200);assert.equal(modified.body.item.active,false);
    ok(await request("POST","/auth/login",{email:employee.email,password:"StaffStrong2026!"}),401);
    ok(await request("PATCH","/users/"+employee.id,{name:"Bibliotecária de testes",email:employee.email,role:"librarian",active:true},cookie),200);
    ok(await request("POST","/users/"+employee.id+"/reset-password",{password:"NovaSenhaFuncionaria_2026!"},cookie),200);
    ok(await request("POST","/auth/login",{email:employee.email,password:"StaffStrong2026!"}),401);
    const staff=await request("POST","/auth/login",{email:employee.email,password:"NovaSenhaFuncionaria_2026!"});
    ok(staff,200);
    ok(await request("PATCH","/users/"+employee.id,{name:"Hacker",email:employee.email,role:"admin",active:true},staff.cookie),403);
    ok(await request("PATCH","/copies/"+copy1+"/status",{status:"available"},staff.cookie),403);
    const corrected=await request("PATCH","/copies/"+copy1+"/status",{status:"available"},cookie);
    ok(corrected,200);assert.equal(corrected.body.item.status,"available");
    const profile=await request("PATCH","/me",{name:"Admin QA Revisado",email:ADMIN_EMAIL},cookie);
    ok(profile,200);assert.equal(profile.body.user.name,"Admin QA Revisado");
  });
  await t.test("dashboard traz dados persistidos",async()=>{
    const dash=await request("GET","/dashboard",undefined,cookie);
    ok(dash,200);
    assert.ok(dash.body.metrics.students>=2);
    assert.ok(dash.body.metrics.books>=1);
    assert.ok(dash.body.metrics.available>=1);
    const report=await request("GET","/reports",undefined,cookie);
    ok(report,200);
    assert.ok(report.body.metrics.students>=2);
    assert.ok(Array.isArray(report.body.popular));
    assert.ok(Array.isArray(report.body.monthly));
  });
  await t.test("landing verde, atendimento e uso real em desktop e celular",async()=>{
    mkdirSync("artifacts",{recursive:true});
    const browser=await chromium.launch({headless:true,...(process.env.BOOKSHARE_CHROME?{executablePath:process.env.BOOKSHARE_CHROME}:{})});
    t.after(async()=>await browser.close());
    const page=await browser.newPage({viewport:{width:1366,height:820}});
    const errors=[];page.on("pageerror",err=>errors.push(err.message));
    await page.goto(BASE,{waitUntil:"networkidle"});
    assert.equal(await page.title(),"BookShare — Sua biblioteca, mais simples");
    await page.locator("#landing:not([hidden])").waitFor();
    await page.screenshot({path:"artifacts/01-landing-desktop.png",fullPage:true});
    await page.locator('#landing [data-action="open-login"]').first().click();
    await page.locator("#login:not([hidden])").waitFor();
    await page.screenshot({path:"artifacts/02-login-desktop.png",fullPage:true});
    await page.locator("#login-form [name=email]").fill(ADMIN_EMAIL);
    await page.locator("#login-form [name=password]").fill(ADMIN_PASSWORD);
    await page.locator("#login-form button[type=submit]").click();
    await page.locator("#workspace:not([hidden])").waitFor();
    await page.locator("#stats .stat").first().waitFor();
    assert.equal(await page.locator(".quick-card").count(),4);
    await page.screenshot({path:"artifacts/03-inicio-desktop.png",fullPage:true});
    await page.locator('[data-route="students"]').click();
    await page.locator('[data-page="students"] [data-modal="student"]').click();
    await page.locator('#modal-form [name=name]').fill("Aluno criado na interface");
    await page.locator('#modal-form [name=registration]').fill("QA-UI-001");
    await page.locator('#modal-form [name=class_name]').fill("1º C");
    await page.locator('#modal-form button[type=submit]').click();
    await page.getByText("Aluno criado na interface",{exact:true}).waitFor();
    await page.screenshot({path:"artifacts/04-alunos-desktop.png",fullPage:true});
    await page.locator('[data-route="books"]').click();
    await page.locator(".book-card").first().waitFor();
    await page.locator(".book-card [data-edit-book]").first().click();
    await page.locator('#modal-form [name=category]').fill("Literatura QA");
    await page.locator('#modal-form button[type=submit]').click();
    await page.locator("#dialog").waitFor({state:"hidden"});
    await page.screenshot({path:"artifacts/05-livros-desktop.png",fullPage:true});
    await page.locator(".book-card [data-manage-copies]").first().click();
    await page.locator(".copy-line").first().waitFor();
    await page.screenshot({path:"artifacts/05a-gerenciar-exemplares.png",fullPage:true});
    await page.locator("#dialog [data-close]").click();
    await page.locator("#dialog").waitFor({state:"hidden"});
    await page.locator('[data-route="loans"]').click();
    await page.locator('[data-page="loans"] [data-modal="loan"]').click();
    await page.locator('#picker-student').fill("Estudante Alpha QA");
    await page.locator('[data-picker="student"] .picker-option').first().click();
    assert.equal(await page.locator('#modal-form [name=student_id]').inputValue(),student1);
    await page.locator('#picker-copy').fill("QA-COPY-002");
    await page.locator('[data-picker="copy"] .picker-option').first().click();
    assert.equal(await page.locator('#modal-form [name=copy_id]').inputValue(),copy2);
    await page.screenshot({path:"artifacts/06a-formulario-emprestimo.png",fullPage:true});
    await page.locator('#modal-form button[type=submit]').click();
    await page.locator('[data-page="loans"] [data-return]').first().waitFor();
    await page.screenshot({path:"artifacts/06-emprestimos-desktop.png",fullPage:true});
    await page.locator('#sidebar [data-route="returns"]').click();
    await page.locator('#returns-search').fill("O livro de teste");
    await page.locator('[data-page="returns"] [data-return]').first().waitFor();
    await page.screenshot({path:"artifacts/07-devolucoes-desktop.png",fullPage:true});
    await page.locator('[data-page="returns"] [data-return]').first().click();
    await page.locator('#modal-form [name=condition]').selectOption("normal");
    await page.locator('#modal-form button[type=submit]').click();
    await page.locator("#dialog").waitFor({state:"hidden"});
    await page.locator('[data-route="reports"]').click();
    await page.locator(".report-stat").first().waitFor();
    await page.screenshot({path:"artifacts/08-relatorios-desktop.png",fullPage:true});
    await page.locator('#sidebar [data-route="users"]').click();
    await page.locator('#users-table tbody tr').first().waitFor();
    await page.screenshot({path:"artifacts/08a-equipe-admin-desktop.png",fullPage:true});
    await page.locator('#users-table [data-edit-user]').last().click();
    await page.locator('#modal-form [name=name]').fill("Atendente de testes");
    await page.locator('#modal-form button[type=submit]').click();
    await page.locator("#dialog").waitFor({state:"hidden"});
    await page.getByText("Atendente de testes",{exact:true}).waitFor();
    await page.locator('#users-table [data-reset-user]').last().click();
    await page.locator('#modal-form [name=password]').fill("SenhaUI_Forte_2026!");
    await page.locator('#modal-form button[type=submit]').click();
    await page.locator("#dialog").waitFor({state:"hidden"});
    await page.locator('#sidebar [data-route="profile"]').click();
    await page.locator('#profile-card .button').click();
    await page.locator('#modal-form [name=name]').fill("Administrador de testes");
    await page.locator('#modal-form button[type=submit]').click();
    await page.locator("#dialog").waitFor({state:"hidden"});
    await page.screenshot({path:"artifacts/08b-meu-perfil.png",fullPage:true});
    assert.deepEqual(errors,[]);
    const mobile=await browser.newPage({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
    mobile.on("pageerror",err=>errors.push(err.message));
    await mobile.goto(BASE,{waitUntil:"networkidle"});
    await mobile.locator("#landing:not([hidden])").waitFor();
    await mobile.screenshot({path:"artifacts/09-landing-mobile.png",fullPage:true});
    await mobile.locator('#landing [data-action="open-login"]').first().click();
    await mobile.screenshot({path:"artifacts/10-login-mobile.png",fullPage:true});
    await mobile.locator("#login-form [name=email]").fill(ADMIN_EMAIL);
    await mobile.locator("#login-form [name=password]").fill(ADMIN_PASSWORD);
    await mobile.locator("#login-form button[type=submit]").click();
    await mobile.locator("#workspace:not([hidden])").waitFor();
    await mobile.screenshot({path:"artifacts/11-inicio-mobile.png",fullPage:true});
    await mobile.locator("#menu-toggle").click();
    await mobile.locator('[data-route="books"]').click();
    await mobile.locator('[data-page="books"]:not([hidden])').waitFor();
    await mobile.locator(".book-card").first().waitFor();
    await mobile.screenshot({path:"artifacts/12-livros-mobile.png",fullPage:true});
    await mobile.locator("#menu-toggle").click();
    await mobile.locator('#sidebar [data-route="loans"]').click();
    await mobile.locator('[data-page="loans"] [data-modal="loan"]').click();
    await mobile.locator("#dialog[open]").waitFor();
    await mobile.screenshot({path:"artifacts/13-emprestimo-mobile.png",fullPage:true});
    const modalFits=await mobile.locator("#dialog").evaluate(el=>{
      const rect=el.getBoundingClientRect();
      return rect.left>=0 && rect.right<=window.innerWidth+1 &&
        rect.top>=0 && rect.bottom<=window.innerHeight+1;
    });
    assert.ok(modalFits,"O formulário de empréstimo não cabe na tela do celular");
    await mobile.locator("#dialog-close").click();
    const noHeaderCollision=await mobile.evaluate(()=>{
      const brand=document.querySelector(".top-brand").getBoundingClientRect();
      const logout=document.querySelector(".top-right .text-button").getBoundingClientRect();
      const menu=document.querySelector(".mobile-menu").getBoundingClientRect();
      return brand.right+2<=logout.left && logout.right+2<=menu.left;
    });
    assert.ok(noHeaderCollision,"Cabeçalho mobile sobreposto");
    const card=await mobile.locator(".book-card").first().evaluate(el=>{
      const cover=el.querySelector(".book-cover").getBoundingClientRect();
      const body=el.querySelector(".book-body").getBoundingClientRect();
      return cover.bottom<=body.top+1 || cover.right<=body.left+1;
    });
    assert.ok(card,"Capa do livro invade informações no celular");
    assert.deepEqual(errors,[]);
  });
  await t.test("usuário consegue trocar senha e senha anterior deixa de funcionar",async()=>{
    const target="NovaSenhaQA_Com_16_Caracteres_2026";
    ok(await request("POST","/me/password",{current_password:"senha errada",new_password:target},cookie),403);
    ok(await request("POST","/me/password",{current_password:ADMIN_PASSWORD,new_password:target},cookie),200);
    ok(await request("POST","/auth/login",{email:ADMIN_EMAIL,password:ADMIN_PASSWORD}),401);
    ok(await request("POST","/auth/login",{email:ADMIN_EMAIL,password:target}),200);
  });
});
