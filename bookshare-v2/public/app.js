"use strict";
const $ = (q,root=document)=>root.querySelector(q);
const $$ = (q,root=document)=>[...root.querySelectorAll(q)];
const state={user:null,route:"home",loanFilter:"active",students:[],books:[],copies:[],loans:[],reservations:[],users:[]};
const plain = x=>String(x??"");
const esc = x=>plain(x).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const fmt = x=> x ? new Date(plain(x).length===10 ? x+"T12:00:00" : x).toLocaleDateString("pt-BR"):"—";
const media = id=> id ? "/api/media/"+encodeURIComponent(id) : null;
const toast=(message,bad=false)=>{
 const el=$("#toast");el.textContent=message;el.className="shown"+(bad?" danger":"");
 clearTimeout(toast.timer);toast.timer=setTimeout(()=>el.className="",4800);
};
async function api(path,options={}){
 let response;
 try{response=await fetch("/api"+path,{credentials:"same-origin",headers:{"Content-Type":"application/json",...(options.headers||{})},...options});}
 catch{throw Error("Sem conexão com o servidor. Tente novamente.");}
 let data;try{data=await response.json();}catch{throw Error("O servidor respondeu em formato inesperado.");}
 if(response.status===401 && !path.includes("/auth/login")){showLogin();throw Error("Sessão expirada. Entre novamente.");}
 if(!response.ok)throw Error(data.error||"Não foi possível concluir a operação.");
 return data;
}
function showLogin(){state.user=null;$("#workspace").hidden=true;$("#login").hidden=false;}
function showApp(user){
 state.user=user;$("#login").hidden=true;$("#workspace").hidden=false;
 $("#user-label").textContent=user.name+" · "+(user.role==="admin"?"Administração":"Biblioteca");
 $$(".admin-only").forEach(el=>el.hidden=user.role!=="admin");
 navigate("home");
}
async function refresh(route=state.route){
 try{
   if(route==="home"){
     const d=await api("/dashboard");renderDashboard(d);
   }else if(route==="books"){
     const q=$("#books-search").value.trim();
     const d=await api("/books?q="+encodeURIComponent(q)+"&limit=100");state.books=d.items;renderBooks(d.items);
   }else if(route==="students"){
     const q=$("#students-search").value.trim();
     const d=await api("/students?q="+encodeURIComponent(q)+"&limit=100");state.students=d.items;renderStudents(d.items);
   }else if(route==="loans"){
     const d=await api("/loans?status="+state.loanFilter+"&limit=200");state.loans=d.items;renderLoans(d.items);
   }else if(route==="reservations"){
     const d=await api("/reservations?limit=100");state.reservations=d.items;renderReservations(d.items);
   }else if(route==="users"){
     if(state.user?.role!=="admin")return navigate("home");
     const d=await api("/users");state.users=d.items;renderUsers(d.items);
   }
 }catch(e){toast(e.message,true);}
}
function navigate(route){
 if(!["home","books","students","loans","reservations","users"].includes(route))route="home";
 if(route==="users" && state.user?.role!=="admin")return;
 state.route=route;
 $$(".page").forEach(el=>el.hidden=el.dataset.page!==route);
 $$(".nav-link").forEach(el=>el.classList.toggle("active",el.dataset.route===route));
 $("#sidebar").classList.remove("open");refresh(route);
}
const message = text=>'<p class="empty">'+esc(text)+'</p>';
const chip=(label,variant="")=>'<span class="pill '+variant+'">'+esc(label)+'</span>';
function renderDashboard(data){
 const m=data.metrics||{};
 const stats=[["Livros cadastrados",m.books],["Exemplares disponíveis",m.available],["Empréstimos ativos",m.active_loans],["Alunos ativos",m.students],["Em atraso",m.overdue],["Reservas pendentes",m.reservations]];
 $("#stats").innerHTML=stats.map(([label,val])=>'<div class="stat"><span>'+esc(label)+'</span><strong>'+esc(val??0)+'</strong></div>').join("");
 $("#attention").innerHTML=(data.attention||[]).map(x=>'<div class="item-line"><div><strong>'+esc(x.book)+'</strong><small>'+esc(x.student)+' · '+esc(x.code)+'</small></div>'+chip(fmt(x.due_date),x.due_date?.slice(0,10)<new Date().toISOString().slice(0,10)?"bad":"warn")+'</div>').join("")||message("Nenhuma devolução urgente. Tudo em dia!");
 $("#recent").innerHTML=(data.recent||[]).map(x=>'<div class="item-line"><div><strong>'+esc(x.book)+'</strong><small>'+esc(x.student)+' · '+fmt(x.loaned_at)+'</small></div>'+chip(x.status==="active"?"Emprestado":"Devolvido",x.status==="active"?"warn":"")+'</div>').join("")||message("Os próximos empréstimos aparecem aqui.");
}
function renderBooks(items){
 $("#books-grid").innerHTML=items.map(x=>'<article class="book-card"><div class="book-cover">'+(x.cover_id?'<img src="'+media(x.cover_id)+'" loading="lazy" alt="Capa de '+esc(x.title)+'">':'<span class="placeholder" aria-hidden="true">▤</span>')+'</div><div class="book-body"><h3>'+esc(x.title)+'</h3><p>'+esc(x.author)+'</p><div class="book-foot">'+chip(x.available+" disponíveis",x.available?"":"warn")+'<button class="small-button" data-add-copy="'+esc(x.id)+'">+ Exemplar</button></div></div></article>').join("")||message("Ainda não há livros no acervo.");
}
function avatar(item){
 return '<div class="avatar">'+(item.photo_id?'<img src="'+media(item.photo_id)+'" alt="">':esc(item.name.slice(0,1).toUpperCase()))+'</div>';
}
function table(head,rows){
 if(!rows.length)return message("Nenhum registro encontrado.");
 return '<table class="data-table"><thead><tr>'+head.map(h=>'<th scope="col">'+esc(h)+'</th>').join("")+'</tr></thead><tbody>'+rows.join("")+'</tbody></table>';
}
function renderStudents(items){
 $("#students-table").innerHTML=table(["Aluno","Matrícula","Turma","Situação",""],items.map(x=>'<tr><td><div class="student-cell">'+avatar(x)+'<strong>'+esc(x.name)+'</strong></div></td><td>'+esc(x.registration)+'</td><td>'+esc(x.class_name)+'</td><td>'+chip(x.active?"Ativo":"Inativo",x.active?"":"warn")+'</td><td><button class="small-button" data-edit-student="'+esc(x.id)+'">Editar</button></td></tr>'));
}
function renderLoans(items){
 $("#loans-table").innerHTML=table(["Livro / exemplar","Aluno","Vencimento","Situação","Ações"],items.map(x=>{
   const actions=x.status==="active"?'<div class="actions"><button class="small-button" data-return="'+esc(x.id)+'">Devolver</button><button class="small-button" data-renew="'+esc(x.id)+'">Renovar</button></div>':"—";
   return '<tr><td><strong>'+esc(x.book)+'</strong><br><span class="muted small">'+esc(x.code)+'</span></td><td>'+esc(x.student)+'</td><td>'+fmt(x.due_date)+'</td><td>'+chip(x.status==="active"?"Em andamento":"Devolvido",x.status==="active"?"warn":"")+'</td><td>'+actions+'</td></tr>';
 }));
}
function renderReservations(items){
 $("#reservations-table").innerHTML=table(["Livro","Aluno","Solicitação","Situação","Ações"],items.map(x=>{
 const words={waiting:"Aguardando",ready:"Disponível",completed:"Concluída",cancelled:"Cancelada"};
 const actions=["waiting","ready"].includes(x.status)?'<div class="actions"><button class="small-button" data-res-status="'+esc(x.id)+'" data-value="'+(x.status==="waiting"?"ready":"completed")+'">'+(x.status==="waiting"?"Disponibilizar":"Concluir")+'</button><button class="small-button danger-text" data-res-status="'+esc(x.id)+'" data-value="cancelled">Cancelar</button></div>':"—";
 return '<tr><td><strong>'+esc(x.book)+'</strong></td><td>'+esc(x.student)+'</td><td>'+fmt(x.created_at)+'</td><td>'+chip(words[x.status]||x.status,x.status==="waiting"?"warn":"")+'</td><td>'+actions+'</td></tr>';
 }));
}
function renderUsers(items){
 $("#users-table").innerHTML=table(["Nome","E-mail","Perfil","Status"],items.map(x=>'<tr><td><strong>'+esc(x.name)+'</strong></td><td>'+esc(x.email)+'</td><td>'+esc(x.role==="admin"?"Administrador":"Bibliotecária")+'</td><td>'+chip(x.active?"Ativo":"Desativado",x.active?"":"warn")+'</td></tr>'));
}
const field=(label,name,placeholder="",type="text",required=true,value="",wide=false)=>'<label class="'+(wide?"wide":"")+'">'+esc(label)+'<input type="'+esc(type)+'" name="'+esc(name)+'" placeholder="'+esc(placeholder)+'" value="'+esc(value)+'" '+(required?"required":"")+'></label>';
const selectField=(label,name,items,required=true)=>'<label>'+esc(label)+'<select name="'+esc(name)+'" '+(required?"required":"")+'>'+items.map(([v,text])=>'<option value="'+esc(v)+'">'+esc(text)+'</option>').join("")+'</select></label>';
const shell=(title,subtitle,fields,submit="Salvar")=>'<p class="eyebrow">BOOKSHARE / CADASTRO</p><h2>'+esc(title)+'</h2><p class="muted">'+esc(subtitle)+'</p><form id="modal-form"><div class="form-grid">'+fields+'</div><div class="form-actions"><button type="button" class="button secondary" data-close>Cancelar</button><button type="submit" class="button primary">'+esc(submit)+'</button></div><p class="error" id="modal-error" role="alert"></p></form>';
const dialog=$("#dialog");
function openDialog(title,subtitle,fields,onSubmit,submit){
 $("#dialog-content").innerHTML=shell(title,subtitle,fields,submit);
 const form=$("#modal-form");
 form.addEventListener("submit",async e=>{
  e.preventDefault();const btn=form.querySelector('[type="submit"]');btn.disabled=true;
  $("#modal-error").textContent="";
  const b=Object.fromEntries(new FormData(form).entries());
  try{await onSubmit(b,form);dialog.close();toast("Operação concluída.");await refresh();}
  catch(err){$("#modal-error").textContent=err.message;}
  finally{btn.disabled=false;}
 });
 dialog.showModal();
}
const getItems=async endpoint=>(await api(endpoint)).items;
const selectOption=items=>items.map(x=>[x.id,x.name||x.title||x.code]);
const imgField=()=>'<label class="wide">Foto ou capa <span class="hint">Opcional · JPG/PNG/WebP até 1,3 MB</span><input type="file" name="image_file" accept="image/png,image/jpeg,image/webp"></label>';
async function uploadImage(form){
 const file=form.querySelector('[name="image_file"]')?.files[0];
 if(!file)return null;
 if(file.size>1300000)throw Error("Imagem muito grande. Máximo: 1,3 MB.");
 const image=await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=()=>reject(Error("Falha na leitura da foto."));reader.readAsDataURL(file)});
 return (await api("/media",{method:"POST",body:JSON.stringify({image})})).id;
}
async function openModal(type,extra){
 if(type==="student"){
   const old=state.students.find(x=>x.id===extra);
   const fields=field("Nome completo","name","Nome do aluno","text",true,old?.name||"",true)+field("Matrícula","registration","Número de matrícula","text",true,old?.registration||"")+field("Turma","class_name","Ex.: 3º B","text",true,old?.class_name||"")+field("Contato","contact","Opcional","text",false,old?.contact||"",true)+imgField();
   openDialog(old?"Editar aluno":"Cadastrar aluno","Informações essenciais do estudante.",fields,async(b,form)=>{
     const photo_id=await uploadImage(form)||old?.photo_id||null;
     await api(old?"/students/"+old.id:"/students",{method:old?"PATCH":"POST",body:JSON.stringify({...b,photo_id,active:old?.active!==false})});
   });
 }
 else if(type==="book"){
   const fields=field("Título","title","Nome do livro","text",true,"",true)+field("Autor","author","Nome do autor","text",true,"",true)+field("ISBN","isbn","Opcional","text",false)+field("Categoria","category","Ex.: Literatura","text",false)+imgField();
   openDialog("Adicionar livro","Cadastre a obra. Os exemplares são adicionados separadamente.",fields,async(b,form)=>{
     const cover_id=await uploadImage(form);
     await api("/books",{method:"POST",body:JSON.stringify({...b,cover_id})});
   });
 }
 else if(type==="copy"){
   const books=await getItems("/books?limit=100");
   if(!books.length)return toast("Cadastre um livro antes de adicionar exemplares.",true);
   const fields=selectField("Livro","book_id",selectOption(books))+field("Código patrimonial","code","Ex.: BIB-001");
   openDialog("Novo exemplar","Cada cópia física tem um código próprio.",fields,async b=>api("/copies",{method:"POST",body:JSON.stringify(b)}));
   if(extra)$("#modal-form [name=book_id]").value=extra;
 }
 else if(type==="loan"){
   const [students,copies]=await Promise.all([getItems("/students?limit=100"),getItems("/copies?limit=200")]);
   const ready=copies.filter(x=>x.status==="available");
   if(!students.length||!ready.length)return toast("Cadastre um aluno e pelo menos um exemplar disponível.",true);
   const due=new Date();due.setDate(due.getDate()+14);
   const dueStr=due.toISOString().slice(0,10);
   const fields=selectField("Aluno","student_id",students.filter(x=>x.active).map(x=>[x.id,x.name+" · "+x.registration]))+selectField("Exemplar disponível","copy_id",ready.map(x=>[x.id,x.title+" · "+x.code]))+field("Data de devolução","due_date","","date",true,dueStr,true);
   openDialog("Novo empréstimo","Selecione aluno, exemplar e vencimento.",fields,async b=>api("/loans",{method:"POST",body:JSON.stringify(b)}),"Registrar empréstimo");
 }
 else if(type==="reservation"){
   const [students,books]=await Promise.all([getItems("/students?limit=100"),getItems("/books?limit=100")]);
   if(!students.length||!books.length)return toast("Cadastre alunos e livros antes de reservar.",true);
   const fields=selectField("Aluno","student_id",students.filter(x=>x.active).map(x=>[x.id,x.name]))+selectField("Livro","book_id",selectOption(books));
   openDialog("Nova reserva","Registre a solicitação de um livro.",fields,async b=>api("/reservations",{method:"POST",body:JSON.stringify(b)}));
 }
 else if(type==="user"){
   if(state.user?.role!=="admin")return;
   const fields=field("Nome","name","Nome completo","text",true,"",true)+field("E-mail","email","email@escola.com","email",true,"",true)+field("Senha (12+ caracteres)","password","Senha inicial","password",true,"",true)+selectField("Perfil","role",[["librarian","Bibliotecária"],["admin","Administrador"]]);
   openDialog("Adicionar pessoa","Defina quem terá acesso à biblioteca.",fields,async b=>api("/users",{method:"POST",body:JSON.stringify(b)}));
 }
 else if(type==="return"){
   const row=state.loans.find(x=>x.id===extra);
   if(!row)return;
   const fields='<div class="wide"><p class="muted">'+esc(row.book)+" · "+esc(row.student)+'</p></div>'+selectField("Condição do exemplar","condition",[["normal","Em boas condições"],["damaged","Danificado"],["lost","Extraviado"]]);
   openDialog("Registrar devolução","O estado do exemplar será atualizado automaticamente.",fields,async b=>api("/loans/"+extra+"/return",{method:"POST",body:JSON.stringify(b)}),"Confirmar devolução");
 }
 else if(type==="renew"){
   const row=state.loans.find(x=>x.id===extra);if(!row)return;
   const due=new Date(row.due_date+"T12:00:00");due.setDate(due.getDate()+14);
   const fields=field("Novo vencimento","due_date","","date",true,due.toISOString().slice(0,10),true);
   openDialog("Renovar empréstimo","A nova data precisa ser posterior à atual. Até duas renovações.",fields,async b=>api("/loans/"+extra+"/renew",{method:"POST",body:JSON.stringify(b)}),"Confirmar renovação");
 }
}
document.addEventListener("click",async e=>{
 const el=e.target.closest("button");if(!el)return;
 if(el.dataset.route){navigate(el.dataset.route);return;}
 if(el.dataset.action==="go-loan"){navigate("loans");await openModal("loan");return;}
 if(el.dataset.modal)return openModal(el.dataset.modal);
 if(el.dataset.close){dialog.close();return;}
 if(el.dataset.addCopy)return openModal("copy",el.dataset.addCopy);
 if(el.dataset.editStudent)return openModal("student",el.dataset.editStudent);
 if(el.dataset.return)return openModal("return",el.dataset.return);
 if(el.dataset.renew)return openModal("renew",el.dataset.renew);
 if(el.dataset.resStatus){
  if(!confirm("Confirmar atualização da reserva?"))return;
  try{await api("/reservations/"+el.dataset.resStatus+"/status",{method:"POST",body:JSON.stringify({status:el.dataset.value})});toast("Reserva atualizada.");await refresh();}
  catch(err){toast(err.message,true);}
 }
 if(el.dataset.loanFilter){state.loanFilter=el.dataset.loanFilter;$$("[data-loan-filter]").forEach(b=>b.classList.toggle("selected",b===el));refresh("loans");}
});
let timer;
["books","students"].forEach(type=>{
 $("#"+type+"-search").addEventListener("input",()=>{clearTimeout(timer);timer=setTimeout(()=>refresh(type),250);});
});
$("#menu-toggle").onclick=()=>$("#sidebar").classList.toggle("open");
$("#logout").onclick=async()=>{try{await api("/auth/logout",{method:"POST",body:"{}"});}catch{}showLogin();};
$("#login-form").addEventListener("submit",async e=>{
 e.preventDefault();const form=e.currentTarget,button=form.querySelector("button");
 button.disabled=true;$("#auth-error").textContent="";
 try{const b=Object.fromEntries(new FormData(form));const d=await api("/auth/login",{method:"POST",body:JSON.stringify(b)});form.reset();showApp(d.user);}
 catch(err){$("#auth-error").textContent=err.message;}
 finally{button.disabled=false;}
});
(async()=>{try{const d=await api("/me");showApp(d.user)}catch{showLogin()}})();
