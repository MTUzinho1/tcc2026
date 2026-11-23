"use strict";
const $ = (q,root=document)=>root.querySelector(q);
const $$ = (q,root=document)=>[...root.querySelectorAll(q)];
const state={user:null,route:"home",loanFilter:"active",bookVisible:24,studentVisible:40,students:[],books:[],copies:[],loans:[],reservations:[],users:[]};
const plain = x=>String(x??"");
const esc = x=>plain(x).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const fmt = x=> x ? new Date(plain(x).length===10 ? x+"T12:00:00" : x).toLocaleDateString("pt-BR"):"—";
const media = id=> id ? "/api/media/"+encodeURIComponent(id) : null;
const legacyCover = raw=>{try{const url=new URL(raw);return url.protocol==="https:" && ["books.google.com","books.googleusercontent.com","covers.openlibrary.org","images-na.ssl-images-amazon.com","m.media-amazon.com"].includes(url.hostname)?url.href:null;}catch{return null;}};
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
function showLogin(){
 state.user=null;$("#landing").hidden=true;$("#workspace").hidden=true;$("#login").hidden=false;window.scrollTo(0,0);
}
function showLanding(){
 state.user=null;$("#workspace").hidden=true;$("#login").hidden=true;$("#landing").hidden=false;window.scrollTo(0,0);
}
function showApp(user){
 state.user=user;$("#landing").hidden=true;$("#login").hidden=true;$("#workspace").hidden=false;
 $("#hello-name").textContent=user.name.split(" ")[0];
 $("#user-label").textContent=user.name.split(" ")[0]+" · "+(user.role==="admin"?"Admin":"Biblioteca");
 $(".profile-avatar").textContent=user.name.slice(0,1).toUpperCase();
 $$(".admin-only").forEach(el=>el.hidden=user.role!=="admin");
 navigate("home");
}
async function refresh(route=state.route){
 try{
  if(route==="home"){
   renderDashboard(await api("/dashboard"));
  }else if(route==="books"){
   const q=$("#books-search").value.trim();
   const d=await api("/books?q="+encodeURIComponent(q)+"&limit=1000");
   state.books=d.items;renderBooks(d.items);
  }else if(route==="students"){
   const q=$("#students-search").value.trim();
   const d=await api("/students?q="+encodeURIComponent(q)+"&limit=1000");
   state.students=d.items;renderStudents(d.items);
  }else if(route==="loans"){
   const d=await api("/loans?status="+state.loanFilter+"&limit=200");state.loans=d.items;renderLoans(d.items);
  }else if(route==="returns"){
   const q=$("#returns-search").value.trim();
   const d=await api("/loans?status=active&limit=200&q="+encodeURIComponent(q));
   state.loans=d.items;renderReturns(d.items);
  }else if(route==="reports"){
   renderReports(await api("/reports"));
  }else if(route==="reservations"){
   const d=await api("/reservations?limit=100");state.reservations=d.items;renderReservations(d.items);
  }else if(route==="users"){
   if(state.user?.role!=="admin")return navigate("home");
   const d=await api("/users");state.users=d.items;renderUsers(d.items);
  }else if(route==="profile"){
   const d=await api("/me");state.user=d.user;renderProfile(d.user);
  }
 }catch(err){toast(err.message,true);}
}
function navigate(route){
 if(!["home","books","students","loans","returns","reports","reservations","users","profile"].includes(route))route="home";
 if(route==="users"&&state.user?.role!=="admin")return;
 state.route=route;
 $$(".page").forEach(el=>el.hidden=el.dataset.page!==route);
 $$(".nav-link").forEach(el=>el.classList.toggle("active",el.dataset.route===route));
 $("#sidebar").classList.remove("open");
 $("#menu-toggle").setAttribute("aria-expanded","false");
 document.title="BookShare — "+({home:"Início",books:"Livros",students:"Alunos",loans:"Empréstimos",returns:"Devoluções",reports:"Relatórios",reservations:"Reservas",users:"Equipe",profile:"Meu perfil"}[route]||"Biblioteca");
 refresh(route);
}
const message = text=>'<p class="empty">'+esc(text)+'</p>';
const chip=(label,variant="")=>'<span class="pill '+variant+'">'+esc(label)+'</span>';
function renderDashboard(data){
 const m=data.metrics||{};
 const stats=[["Livros no acervo",m.books],["Alunos cadastrados",m.students],["Empréstimos ativos",m.active_loans],["Em atraso",m.overdue]];
 $("#stats").innerHTML=stats.map(([label,val])=>'<div class="stat"><span>'+esc(label)+'</span><strong>'+esc(val??0)+'</strong></div>').join("");
 $("#attention").innerHTML=(data.attention||[]).map(x=>'<div class="item-line"><div><strong>'+esc(x.book)+'</strong><small>'+esc(x.student)+' · '+esc(x.code)+'</small></div>'+chip(fmt(x.due_date),x.due_date?.slice(0,10)<new Date().toISOString().slice(0,10)?"bad":"warn")+'</div>').join("")||message("Nenhuma devolução urgente. Tudo em dia!");
 $("#recent").innerHTML=(data.recent||[]).map(x=>'<div class="item-line"><div><strong>'+esc(x.book)+'</strong><small>'+esc(x.student)+' · '+fmt(x.loaned_at)+'</small></div>'+chip(x.status==="active"?"Emprestado":"Devolvido",x.status==="active"?"warn":"")+'</div>').join("")||message("Os próximos empréstimos aparecem aqui.");
}
function renderBooks(items){
 const rows=items.slice(0,state.bookVisible);
 $("#books-grid").innerHTML=rows.map(x=>{
   const url=x.cover_id?media(x.cover_id):legacyCover(x.cover_url);
   const cover=url?'<img src="'+esc(url)+'" loading="lazy" referrerpolicy="no-referrer" alt="Capa de '+esc(x.title)+'">':'<span class="placeholder" aria-hidden="true">▤</span>';
   return '<article class="book-card"><div class="book-cover">'+cover+'</div><div class="book-body"><h3>'+esc(x.title)+'</h3><p>'+esc(x.author)+'</p><div class="book-foot">'+chip(x.available+" disponíveis",x.available?"":"warn")+'<button class="small-button" data-add-copy="'+esc(x.id)+'">+ Exemplar</button><button class="small-button secondary-edit" data-edit-book="'+esc(x.id)+'">Editar</button></div></div></article>';
 }).join("")||message("Ainda não há livros no acervo.");
 $("#books-count").textContent=items.length+" título"+(items.length===1?"":"s");
 if(items.length>rows.length)$("#books-grid").insertAdjacentHTML("beforeend",'<div class="load-more"><button class="button secondary" data-more="books">Mostrar mais livros ('+esc(items.length-rows.length)+')</button></div>');
}
function avatar(item){
 return '<div class="avatar">'+(item.photo_id?'<img src="'+media(item.photo_id)+'" alt="">':esc(item.name.slice(0,1).toUpperCase()))+'</div>';
}
function table(head,rows){
 if(!rows.length)return message("Nenhum registro encontrado.");
 return '<table class="data-table"><thead><tr>'+head.map(h=>'<th scope="col">'+esc(h)+'</th>').join("")+'</tr></thead><tbody>'+rows.join("")+'</tbody></table>';
}
function renderStudents(items){
 const rows=items.slice(0,state.studentVisible);
 $("#students-table").innerHTML=table(["Aluno","Matrícula","Turma","Situação",""],rows.map(x=>'<tr><td><div class="student-cell">'+avatar(x)+'<strong>'+esc(x.name)+'</strong></div></td><td>'+esc(x.registration)+'</td><td>'+esc(x.class_name)+'</td><td>'+chip(x.active?"Ativo":"Inativo",x.active?"":"warn")+'</td><td><button class="small-button" data-edit-student="'+esc(x.id)+'">Editar</button></td></tr>'));
 $("#students-count").textContent=items.length+" aluno"+(items.length===1?"":"s");
 if(items.length>rows.length)$("#students-table").insertAdjacentHTML("beforeend",'<div class="load-more"><button class="button secondary" data-more="students">Mostrar mais alunos ('+esc(items.length-rows.length)+')</button></div>');
}
function renderLoans(items){
 $("#loans-table").innerHTML=table(["Livro / exemplar","Aluno","Vencimento","Situação","Ações"],items.map(x=>{
   const actions=x.status==="active"?'<div class="actions"><button class="small-button" data-return="'+esc(x.id)+'">Devolver</button><button class="small-button" data-renew="'+esc(x.id)+'">Renovar</button></div>':"—";
   return '<tr><td><strong>'+esc(x.book)+'</strong><br><span class="muted small">'+esc(x.code)+'</span></td><td>'+esc(x.student)+'</td><td>'+fmt(x.due_date)+'</td><td>'+chip(x.status==="active"?"Em andamento":"Devolvido",x.status==="active"?"warn":"")+'</td><td>'+actions+'</td></tr>';
 }));
}
function renderReturns(items){
 $("#returns-table").innerHTML=table(["Livro / exemplar","Aluno","Data prevista","Ação"],items.map(x=>
  '<tr><td><strong>'+esc(x.book)+'</strong><br><span class="muted small">'+esc(x.code)+'</span></td><td>'+esc(x.student)+'</td><td>'+fmt(x.due_date)+'</td><td><button class="small-button" data-return="'+esc(x.id)+'">Devolver livro</button></td></tr>'
 ));
}
function renderReports(data){
 const m=data.metrics||{}, popular=data.popular||[], monthly=data.monthly||[];
 const cards=[["Alunos ativos",m.students],["Livros cadastrados",m.books],["Exemplares disponíveis",m.available],["Empréstimos em andamento",m.active_loans],["Em atraso",m.overdue],["Devoluções registradas",m.returned]];
 const summary='<div class="report-grid">'+cards.map(([name,n])=>'<div class="report-stat"><strong>'+esc(n??0)+'</strong><span>'+esc(name)+'</span></div>').join("")+'</div>';
 const max=Math.max(1,...monthly.map(x=>Number(x.total)||0));
 const chart=monthly.map(x=>'<div class="item-line"><div style="flex:1"><strong>'+esc(x.month)+'</strong><div class="report-bar"><span style="width:'+Math.round((Number(x.total)||0)/max*100)+'%"></span></div></div><b>'+esc(x.total)+'</b></div>').join("")||message("Nenhum empréstimo registrado.");
 const top=popular.map((x,i)=>'<div class="item-line"><div><strong>'+(i+1)+'. '+esc(x.title)+'</strong><small>'+esc(x.author)+'</small></div><span class="pill">'+esc(x.total)+' empréstimos</span></div>').join("")||message("Sem empréstimos suficientes para listar livros.");
 $("#report-content").innerHTML=summary+'<div class="two-columns report-list"><article class="surface"><h2>Empréstimos por mês</h2>'+chart+'</article><article class="surface"><h2>Livros mais emprestados</h2>'+top+'</article></div>';
}
function renderReservations(items){
 $("#reservations-table").innerHTML=table(["Livro","Aluno","Solicitação","Situação","Ações"],items.map(x=>{
 const words={waiting:"Aguardando",ready:"Disponível",completed:"Concluída",cancelled:"Cancelada"};
 const actions=["waiting","ready"].includes(x.status)?'<div class="actions">'+(x.status==="waiting"?'<button class="small-button" data-res-status="'+esc(x.id)+'" data-value="ready">Disponibilizar</button>':'<button class="small-button" data-pickup="'+esc(x.id)+'">Registrar retirada</button>')+'<button class="small-button danger-text" data-res-status="'+esc(x.id)+'" data-value="cancelled">Cancelar</button></div>':"—";
 return '<tr><td><strong>'+esc(x.book)+'</strong></td><td>'+esc(x.student)+'</td><td>'+fmt(x.created_at)+'</td><td>'+chip(words[x.status]||x.status,x.status==="waiting"?"warn":"")+'</td><td>'+actions+'</td></tr>';
 }));
}
function renderUsers(items){
 const q=($("#users-search")?.value||"").normalize("NFD").replace(/[\u0300-\u036f]/g,"").toLowerCase().trim();
 const filtered=items.filter(x=>(x.name+" "+x.email).normalize("NFD").replace(/[\u0300-\u036f]/g,"").toLowerCase().includes(q));
 $("#users-count").textContent=filtered.length+" pessoa"+(filtered.length===1?"":"s");
 $("#users-summary").innerHTML=[
  ["Pessoas cadastradas",items.length],
  ["Com acesso ativo",items.filter(x=>x.active).length],
  ["Administradores ativos",items.filter(x=>x.active&&x.role==="admin").length]
 ].map(([name,n])=>'<div class="team-kpi"><span>'+esc(name)+'</span><strong>'+n+'</strong></div>').join("");
 $("#users-table").innerHTML=table(["Funcionário","E-mail","Perfil","Acesso","Ações"],filtered.map(x=>
  '<tr><td><strong>'+esc(x.name)+'</strong></td><td>'+esc(x.email)+'</td><td>'+esc(x.role==="admin"?"Administrador":"Bibliotecária")+'</td><td>'+chip(x.active?"Ativo":"Desativado",x.active?"":"warn")+'</td>'+
  '<td><div class="actions"><button class="small-button" data-edit-user="'+esc(x.id)+'">Editar</button><button class="small-button" data-reset-user="'+esc(x.id)+'">Senha</button><button class="small-button '+(x.active?"danger-text":"")+'" data-toggle-user="'+esc(x.id)+'">'+(x.active?"Desativar":"Ativar")+'</button></div></td></tr>'
 ));
}
function renderProfile(user){
 $("#profile-card").innerHTML='<span class="profile-large-avatar">'+esc(user.name.slice(0,1).toUpperCase())+'</span>'+
  '<h2>'+esc(user.name)+'</h2><p class="muted">'+esc(user.role==="admin"?"Administrador":"Bibliotecária")+'</p>'+
  '<div class="profile-data"><span>E-mail</span><strong>'+esc(user.email)+'</strong></div>'+
  '<div class="profile-data"><span>Perfil de acesso</span><strong>'+esc(user.role==="admin"?"Administração":"Biblioteca")+'</strong></div>'+
  '<button class="button primary" data-modal="profile">Editar meus dados</button>';
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
   const fields=field("Nome completo","name","Nome do aluno","text",true,old?.name||"",true)
     +field("Matrícula","registration","Número de matrícula","text",true,old?.registration||"")
     +field("Turma","class_name","Ex.: 3º B","text",true,old?.class_name||"")
     +field("Contato","contact","Opcional","text",false,old?.contact||"",true)
     +(old?selectField("Situação","active",[["true","Ativo"],["false","Inativo"]]):"")
     +imgField();
   openDialog(old?"Editar aluno":"Cadastrar aluno","Informações essenciais do estudante.",fields,async(b,form)=>{
     const photo_id=await uploadImage(form)||old?.photo_id||null;
     await api(old?"/students/"+old.id:"/students",{method:old?"PATCH":"POST",body:JSON.stringify({...b,photo_id,active:b.active!=="false"})});
   },old?"Salvar alterações":"Cadastrar aluno");
   if(old)$("#modal-form [name=active]").value=old.active?"true":"false";
 }
 else if(type==="book"){
   const old=state.books.find(x=>x.id===extra);
   const fields=field("Título","title","Nome do livro","text",true,old?.title||"",true)
     +field("Autor","author","Nome do autor","text",true,old?.author||"",true)
     +field("ISBN","isbn","Opcional","text",false,old?.isbn||"")
     +field("Categoria","category","Ex.: Literatura","text",false,old?.category||"")
     +imgField();
   openDialog(old?"Editar livro":"Cadastrar livro",old?"Atualize os dados e mantenha os exemplares registrados.":"Cadastre a obra e, em seguida, adicione exemplares.",fields,async(b,form)=>{
     const cover_id=await uploadImage(form)||old?.cover_id||null;
     await api(old?"/books/"+old.id:"/books",{method:old?"PATCH":"POST",body:JSON.stringify({...b,cover_id})});
   },old?"Salvar alterações":"Cadastrar livro");
 }
 else if(type==="copy"){
   const books=await getItems("/books?limit=1000");
   if(!books.length)return toast("Cadastre um livro antes de adicionar exemplares.",true);
   const fields=selectField("Livro","book_id",selectOption(books))+field("Código patrimonial","code","Ex.: BIB-001");
   openDialog("Novo exemplar","Cada cópia física tem um código próprio.",fields,async b=>api("/copies",{method:"POST",body:JSON.stringify(b)}));
   if(extra)$("#modal-form [name=book_id]").value=extra;
 }
 else if(type==="loan"){
   const [students,copies]=await Promise.all([getItems("/students?limit=1000"),getItems("/copies?limit=1000")]);
   const activeStudents=students.filter(x=>x.active);
   const ready=copies.filter(x=>x.status==="available");
   if(!activeStudents.length||!ready.length)return toast("Cadastre alunos e exemplares disponíveis antes de emprestar.",true);
   const due=new Date();due.setDate(due.getDate()+14);
   const date=due.toISOString().slice(0,10);
   const searchSelect=(label,searchName,selectName,placeholder)=>'<label class="wide">'+esc(label)+'<input type="search" name="'+searchName+'" placeholder="'+esc(placeholder)+'" autocomplete="off"></label><label class="wide">Escolha na lista<select name="'+selectName+'" required><option value="">Selecione</option></select></label>';
   const fields=searchSelect("1. Buscar aluno","student_search","student_id","Digite nome ou matrícula")
      +searchSelect("2. Buscar livro","copy_search","copy_id","Digite título ou código")
      +field("3. Data prevista para devolução","due_date","","date",true,date,true);
   openDialog("Fazer empréstimo","Procure o aluno e o livro. Depois confirme a data.",fields,async b=>{
     if(!b.student_id||!b.copy_id)throw Error("É necessário selecionar o aluno e o livro.");
     await api("/loans",{method:"POST",body:JSON.stringify({student_id:b.student_id,copy_id:b.copy_id,due_date:b.due_date})});
   },"Confirmar empréstimo");
   const form=$("#modal-form");
   const bind=(searchName,selectName,items,labelFn)=>{
     const input=form.querySelector('[name="'+searchName+'"]');
     const select=form.querySelector('[name="'+selectName+'"]');
     const normalize=v=>v.normalize("NFD").replace(/[\u0300-\u036f]/g,"").toLowerCase();
     const update=()=>{
       const q=normalize(input.value.trim());
       const previous=select.value;
       const list=items.filter(x=>normalize(labelFn(x)).includes(q)).slice(0,40);
       select.replaceChildren(new Option(list.length?"Selecione uma opção":"Nenhum resultado encontrado",""));
       for(const item of list)select.add(new Option(labelFn(item),item.id));
       if(list.some(x=>x.id===previous))select.value=previous;
     };
     input.addEventListener("input",update);update();
     return {input,select,update};
   };
   const a=bind("student_search","student_id",activeStudents,x=>x.name+" · "+x.registration);
   const b=bind("copy_search","copy_id",ready,x=>x.title+" · "+x.code);
   if(extra?.student_id){const selected=activeStudents.find(x=>x.id===extra.student_id);if(selected){a.input.value=selected.name;a.update();a.select.value=selected.id;}}
   if(extra?.book_id){const selected=ready.find(x=>x.book_id===extra.book_id);if(selected){b.input.value=selected.title;b.update();b.select.value=selected.id;}}
  }
 else if(type==="reservation"){
   const [students,books]=await Promise.all([getItems("/students?limit=1000"),getItems("/books?limit=1000")]);
   if(!students.length||!books.length)return toast("Cadastre alunos e livros antes de reservar.",true);
   const fields=selectField("Aluno","student_id",students.filter(x=>x.active).map(x=>[x.id,x.name]))+selectField("Livro","book_id",selectOption(books));
   openDialog("Nova reserva","Registre a solicitação de um livro.",fields,async b=>api("/reservations",{method:"POST",body:JSON.stringify(b)}));
 }
 else if(type==="password"){
   const fields=field("Senha atual","current_password","Senha atual","password",true,"",true)+field("Nova senha (mínimo 12 caracteres)","new_password","Nova senha","password",true,"",true);
   openDialog("Alterar minha senha","Escolha uma senha forte que você não usa em outros serviços.",fields,async b=>api("/me/password",{method:"POST",body:JSON.stringify(b)}),"Atualizar senha");
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
   const due=new Date(String(row.due_date).slice(0,10)+"T12:00:00");due.setDate(due.getDate()+14);
   const fields=field("Novo vencimento","due_date","","date",true,due.toISOString().slice(0,10),true);
   openDialog("Renovar empréstimo","A nova data precisa ser posterior à atual. Até duas renovações.",fields,async b=>api("/loans/"+extra+"/renew",{method:"POST",body:JSON.stringify(b)}),"Confirmar renovação");
 }
}
document.addEventListener("click",async e=>{
 const el=e.target.closest("button");if(!el)return;
 if(el.dataset.route){navigate(el.dataset.route);return;}
 if(el.dataset.more==="books"){state.bookVisible+=24;renderBooks(state.books);return;}
 if(el.dataset.more==="students"){state.studentVisible+=40;renderStudents(state.students);return;}
 if(el.dataset.action==="go-loan"){navigate("loans");await openModal("loan");return;}
 if(el.dataset.action==="open-login"){showLogin();return;}
 if(el.dataset.action==="back-landing"){showLanding();return;}
 if(el.dataset.action==="print-reports"){window.print();return;}
 if(el.dataset.modal)return openModal(el.dataset.modal);
 if(el.dataset.close){dialog.close();return;}
 if(el.dataset.addCopy)return openModal("copy",el.dataset.addCopy);
 if(el.dataset.editStudent)return openModal("student",el.dataset.editStudent);
  if(el.dataset.editBook)return openModal("book",el.dataset.editBook);
 if(el.dataset.return)return openModal("return",el.dataset.return);
 if(el.dataset.renew)return openModal("renew",el.dataset.renew);
 if(el.dataset.pickup){const reservation=state.reservations.find(x=>x.id===el.dataset.pickup);if(reservation)await openModal("loan",{student_id:reservation.student_id,book_id:reservation.book_id});return;}
 if(el.dataset.resStatus){
  if(!confirm("Confirmar atualização da reserva?"))return;
  try{await api("/reservations/"+el.dataset.resStatus+"/status",{method:"POST",body:JSON.stringify({status:el.dataset.value})});toast("Reserva atualizada.");await refresh();}
  catch(err){toast(err.message,true);}
 }
 if(el.dataset.loanFilter){state.loanFilter=el.dataset.loanFilter;$$("[data-loan-filter]").forEach(b=>b.classList.toggle("selected",b===el));refresh("loans");}
});
let timer;
["books","students","returns"].forEach(type=>{
 $("#"+type+"-search").addEventListener("input",()=>{clearTimeout(timer);if(type==="books")state.bookVisible=24;else if(type==="students")state.studentVisible=40;timer=setTimeout(()=>refresh(type),250);});
});
$("#menu-toggle").onclick=()=>{
 const opened=$("#sidebar").classList.toggle("open");
 $("#menu-toggle").setAttribute("aria-expanded",String(opened));
};
$("#logout").onclick=async()=>{try{await api("/auth/logout",{method:"POST",body:"{}"});}catch{}showLanding();};
$("#login-form").addEventListener("submit",async e=>{
 e.preventDefault();const form=e.currentTarget,button=form.querySelector("button");
 button.disabled=true;$("#auth-error").textContent="";
 try{const b=Object.fromEntries(new FormData(form));const d=await api("/auth/login",{method:"POST",body:JSON.stringify(b)});form.reset();showApp(d.user);}
 catch(err){$("#auth-error").textContent=err.message;}
 finally{button.disabled=false;}
});
document.querySelector('[data-action-link="landing"]')?.addEventListener("click",e=>{e.preventDefault();showLanding();});
(async()=>{
 try{
  const response=await fetch("/api/me",{credentials:"same-origin"});
  if(!response.ok){showLanding();return;}
  const d=await response.json();showApp(d.user);
 }catch{showLanding();}
})();
