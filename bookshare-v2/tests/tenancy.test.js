import test from "node:test";
import assert from "node:assert/strict";
import {spawn} from "node:child_process";
import {Client} from "pg";
import bcrypt from "bcryptjs";
import {chromium} from "playwright";
import {mkdirSync} from "node:fs";
const base="http://127.0.0.1:3155",email="school-qa@bookshare.test",password="Test_School_Admin_2026!";
const pause=ms=>new Promise(r=>setTimeout(r,ms));
const send=async(method,path,cookie=null,school=null,body=undefined)=>{
 const response=await fetch(base+"/api"+path,{method,headers:{
  ...(cookie?{Cookie:cookie}:{}),...(school?{"x-school-id":school}:{}),
  ...(["POST","PATCH","DELETE"].includes(method)?{Origin:base}:{}),
  ...(body?{"Content-Type":"application/json"}:{})
 },...(body?{body:JSON.stringify(body)}:{})});
 return {status:response.status,body:await response.json().catch(()=>null),cookie:response.headers.get("set-cookie")?.split(";")[0]};
};
test("escolas independentes e exclusões com proteção", {timeout:60000},async t=>{
 const db=new Client({connectionString:process.env.DATABASE_URL});await db.connect();
 const home="00000000-0000-4000-8000-000000000010";
 const hash=await bcrypt.hash(password,10);
 await db.query("INSERT INTO bookshare_v2.users(name,email,password_hash,role,school_id) VALUES($1,$2,$3,'admin',$4)",["Administrador QA Escolas",email,hash,home]);
 t.after(async()=>{await db.query("DELETE FROM bookshare_v2.users WHERE email=$1",[email]);await db.end()});
 const server=spawn(process.execPath,["src/server.js"],{env:{...process.env,PORT:"3155",APP_ORIGIN:base,
   NODE_ENV:"test",JWT_SECRET:"school_testing_secret_long_enough_2026"},stdio:["ignore","pipe","pipe"]});
 t.after(()=>server.kill());
 let ok=false;for(let i=0;i<80;i++){try{if((await send("GET","/health")).status===200){ok=true;break}}catch{}await pause(150)}
 assert.ok(ok,"A API precisa iniciar");
 const auth=await send("POST","/auth/login",null,null,{email,password});
 assert.equal(auth.status,200);
 const cookie=auth.cookie;
 const result=await send("POST","/schools",cookie,null,{name:"Escola QA",city:"Araucária",state:"PR"});
 assert.equal(result.status,201);const school=result.body.item.id;
 const empty=await send("GET","/students",cookie,school);
 assert.equal(empty.status,200);assert.equal(empty.body.items.length,0);
 const student=await send("POST","/students",cookie,school,{name:"Aluno Exemplo",registration:"QA-001",class_name:"1º A"});
 assert.equal(student.status,201);
 const book=await send("POST","/books",cookie,school,{title:"Livro Exemplo",author:"Autores de Teste"});
 assert.equal(book.status,201);
 const avatar=await fetch(base+"/api/students/"+student.body.item.id+"/avatar",{headers:{Cookie:cookie,"x-school-id":school}});
 assert.equal(avatar.status,200);assert.match(avatar.headers.get("content-type"),/^image\//);
 const cover=await fetch(base+"/api/books/"+book.body.item.id+"/cover",{headers:{Cookie:cookie,"x-school-id":school}});
 assert.equal(cover.status,200);assert.match(cover.headers.get("content-type"),/^image\//);
 assert.equal((await send("DELETE","/schools/"+school,cookie)).status,409);
 assert.equal((await send("DELETE","/books/"+book.body.item.id,cookie,school)).status,200);
 assert.equal((await send("DELETE","/students/"+student.body.item.id,cookie,school)).status,200);
 assert.equal((await send("DELETE","/schools/"+school,cookie)).status,200);
 const browser=await chromium.launch({headless:true,...(process.env.BOOKSHARE_CHROME?{executablePath:process.env.BOOKSHARE_CHROME}:{})});
 t.after(()=>browser.close());
 mkdirSync("artifacts",{recursive:true});
 const page=await browser.newPage({viewport:{width:1366,height:820}});
 const errors=[];page.on("pageerror",error=>errors.push(error.message));
 await page.goto(base,{waitUntil:"networkidle"});
 await page.locator('#landing [data-action="open-login"]').first().click();
 await page.locator('#login-form [name=email]').fill(email);
 await page.locator('#login-form [name=password]').fill(password);
 await page.locator('#login-form button[type=submit]').click();
 await page.locator('#workspace:not([hidden])').waitFor();
 await page.locator('#sidebar [data-route="schools"]').click();
 await page.locator('#schools-table tbody tr').first().waitFor();
 await page.screenshot({path:"artifacts/14-escolas-admin.png",fullPage:true});
 await page.locator('[data-page="schools"] [data-modal="school"]').click();
 await page.locator('#modal-form [name=name]').fill("Escola Pela Interface");
 await page.locator('#modal-form [name=city]').fill("Araucária");
 await page.locator('#modal-form [name=state]').fill("PR");
 await page.screenshot({path:"artifacts/15-cadastro-escola.png",fullPage:true});
 await page.locator('#modal-form button[type=submit]').click();
 await page.locator("#dialog").waitFor({state:"hidden"});
 await page.locator("#schools-table strong").getByText("Escola Pela Interface",{exact:true}).waitFor();
 await page.screenshot({path:"artifacts/16-escola-cadastrada.png",fullPage:true});
 const schoolChoice=await page.locator('#school-selector').inputValue();
 assert.ok(schoolChoice);
 await page.locator('[data-delete-school="'+schoolChoice+'"]').click();
 await page.locator('#modal-form [name=confirmation]').fill("EXCLUIR");
 await page.locator('#modal-form button[type=submit]').click();
 await page.locator("#dialog").waitFor({state:"hidden"});
 assert.deepEqual(errors,[]);
 const mobile=await browser.newPage({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
 await mobile.goto(base,{waitUntil:"networkidle"});
 await mobile.locator('#landing [data-action="open-login"]').first().click();
 await mobile.locator('#login-form [name=email]').fill(email);
 await mobile.locator('#login-form [name=password]').fill(password);
 await mobile.locator('#login-form button[type=submit]').click();
 await mobile.locator('#workspace:not([hidden])').waitFor();
 await mobile.screenshot({path:"artifacts/17-seletor-escola-mobile.png",fullPage:true});
 const header=await mobile.evaluate(()=>{
   const brand=document.querySelector(".top-brand").getBoundingClientRect();
   const selector=document.querySelector(".school-context").getBoundingClientRect();
   const logout=document.querySelector("#logout").getBoundingClientRect();
   const menu=document.querySelector("#menu-toggle").getBoundingClientRect();
   return brand.right<=selector.left+1 && selector.right<=logout.left+1 && logout.right<=menu.left+1;
 });
 assert.ok(header,"Elementos do cabeçalho mobile estão sobrepostos");
});
