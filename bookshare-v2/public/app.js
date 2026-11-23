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
   return '<article class="book-card"><div class="book-cover">'+cover+'</div><div class="book-body"><h3>'+esc(x.title)+'</h3><p>'+esc(x.author)+'</p><div class="book-foot">'+chip(x.available+" disponíveis",x.available?"":"warn")+'<button class="small-button" data-add-copy="'+esc(x.id)+'">+ Exemplar</button><button class="small-button secondary-edit" data-edit-book="'+esc(x.id)+'">Editar</button><button class="small-button secondary-edit" data-manage-copies="'+esc(x.id)+'">Exemplares</button></div></div></article>';
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

function pickerHtml(kind,label,placeholder){
 const id="picker-"+kind;
 return '<div class="entity-picker" data-picker="'+esc(kind)+'"><label for="'+id+'">'+esc(label)+'</label>'+
  '<div class="picker-input-wrap"><svg class="ico" aria-hidden="true"><use href="#search"/></svg><input id="'+id+'" type="search" name="'+esc(kind)+'_search" placeholder="'+esc(placeholder)+'" autocomplete="off" role="combobox" aria-autocomplete="list" aria-expanded="false" aria-controls="'+id+'-results"></div>'+
  '<input type="hidden" name="'+esc(kind)+'_id"><div class="picker-results" id="'+id+'-results" role="listbox" hidden></div>'+
  '<div class="picker-selected" hidden><span class="picker-selected-icon">✓</span><span class="picker-chosen"></span><button type="button" class="picker-change">Trocar</button></div></div>';
}
function bindPicker(form,kind,items,labelFn,descFn,selectedCb){
 const container=form.querySelector('[data-picker="'+kind+'"]');
 const search=container.querySelector('input[type="search"]');
 const value=container.querySelector('input[type="hidden"]');
 const results=container.querySelector('.picker-results');
 const selected=container.querySelector('.picker-selected');
 const chosen=container.querySelector('.picker-chosen');
 const change=container.querySelector('.picker-change');
 let current=null;
 const norm=v=>String(v??"").normalize("NFD").replace(/[\u0300-\u036f]/g,"").toLowerCase();
 function close(){results.hidden=true;search.setAttribute("aria-expanded","false")}
 function choose(item){
   current=item;value.value=item.id;search.value=labelFn(item);search.hidden=true;
   chosen.textContent=labelFn(item)+" · "+descFn(item);
   selected.hidden=false;close();selectedCb?.();
 }
 function draw(){
   results.replaceChildren();
   if(!search.value.trim()){close();return;}
   const q=norm(search.value.trim());
   const matching=items.filter(item=>norm(labelFn(item)+" "+descFn(item)).includes(q)).slice(0,7);
   for(const item of matching){
     const row=document.createElement("button");row.type="button";row.className="picker-option";row.setAttribute("role","option");
     const title=document.createElement("strong");title.textContent=labelFn(item);
     const desc=document.createElement("small");desc.textContent=descFn(item);
     row.append(title,desc);row.addEventListener("click",()=>choose(item));results.append(row);
   }
   if(!matching.length){
     const empty=document.createElement("p");empty.className="picker-no-results";empty.textContent="Nenhum resultado. Tente outra busca.";results.append(empty);
   }
   results.hidden=false;search.setAttribute("aria-expanded","true");
 }
 search.addEventListener("input",()=>{current=null;value.value="";selectedCb?.();draw()});
 search.addEventListener("focus",draw);
 search.addEventListener("keydown",event=>{
   if(event.key==="Escape")close();
   if(event.key==="ArrowDown"&&!results.hidden){event.preventDefault();results.querySelector("button")?.focus();}
   if(event.key==="Enter"&&!results.hidden){
     const first=results.querySelector("button");if(first){event.preventDefault();first.click();}
   }
 });
 results.addEventListener("keydown",event=>{
   const buttons=[...results.querySelectorAll("button")];const idx=buttons.indexOf(document.activeElement);
   if(event.key==="ArrowDown"){event.preventDefault();buttons[Math.min(idx+1,buttons.length-1)]?.focus();}
   if(event.key==="ArrowUp"){event.preventDefault();if(idx===0)search.focus();else buttons[idx-1]?.focus();}
   if(event.key==="Escape"){close();search.focus();}
 });
 change.addEventListener("click",()=>{selected.hidden=true;search.hidden=false;search.value="";value.value="";current=null;selectedCb?.();search.focus()});
 return {choose,clear:()=>change.click(),search,get selected(){return current}};
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
 else if(type==="copies"){
   const book=state.books.find(x=>x.id===extra);
   if(!book)return;
   const all=await getItems("/copies?book_id="+encodeURIComponent(book.id)+"&limit=1000");
   const labels={available:"Disponível",loaned:"Emprestado",damaged:"Danificado",lost:"Extraviado"};
   const entries=all.map(c=>{
     const actions=state.user?.role==="admin" && c.status!=="loaned"?
       '<div class="copy-actions">'+(c.status!=="available"?'<button class="small-button" data-copy-action="'+esc(c.id)+'" data-status="available" data-book="'+esc(book.id)+'">Disponibilizar</button>':'<button class="small-button" data-copy-action="'+esc(c.id)+'" data-status="damaged" data-book="'+esc(book.id)+'">Marcar danificado</button>')+
       (c.status!=="lost"?'<button class="small-button danger-text" data-copy-action="'+esc(c.id)+'" data-status="lost" data-book="'+esc(book.id)+'">Extraviado</button>':'')+'</div>':'';
     return '<div class="copy-line"><div><strong>'+esc(c.code)+'</strong><small>'+esc(labels[c.status]||c.status)+'</small></div>'+actions+'</div>';
   }).join("")||message("Ainda não há exemplares deste livro.");
   $("#dialog-content").innerHTML='<div class="modal-heading"><span class="eyebrow">ACERVO · EXEMPLARES</span><h2 id="dialog-heading">'+esc(book.title)+'</h2><p class="muted">Acompanhe cada exemplar físico.</p></div>'+
      '<div class="copy-list">'+entries+'</div><div class="form-actions"><button class="button secondary" type="button" data-close>Fechar</button><button class="button primary" type="button" data-add-copy="'+esc(book.id)+'">+ Adicionar exemplar</button></div>';
   dialog.showModal();
  }
 else if(type==="loan"){
   const [students,copies]=await Promise.all([getItems("/students?limit=1000"),getItems("/copies?limit=1000")]);
   const activeStudents=students.filter(x=>x.active);
   const ready=copies.filter(x=>x.status==="available");
   if(!activeStudents.length || !ready.length)return toast("É necessário ter um aluno ativo e um exemplar disponível.",true);
   const date=new Date();date.setDate(date.getDate()+14);
   const due=date.toISOString().slice(0,10);
   const fields='<div class="loan-ui wide"><div class="loan-two">'+
      pickerHtml("student","1  Quem vai levar?","Digite o nome ou matrícula do aluno")+
      pickerHtml("copy","2  Qual livro?","Digite o título ou código do exemplar")+
      '</div><div class="loan-bottom">'+field("3  Devolver até","due_date","","date",true,due,true)+
      '<div class="loan-summary" aria-live="polite"><strong>Confira antes de registrar</strong><span id="loan-check-name">Selecione um aluno</span><span id="loan-check-book">Selecione um livro</span></div></div></div>';
   openDialog("Novo empréstimo","Encontre o aluno, escolha o livro e confirme. Só isso.",fields,async b=>{
     if(!b.student_id || !b.copy_id)throw Error("Selecione um aluno e um livro nas sugestões.");
     await api("/loans",{method:"POST",body:JSON.stringify({student_id:b.student_id,copy_id:b.copy_id,due_date:b.due_date})});
   },"Confirmar empréstimo");
   dialog.classList.add("dialog-loan");
   dialog.addEventListener("close",()=>dialog.classList.remove("dialog-loan"),{once:true});
   const form=$("#modal-form");
   let student,copy;
   const update=()=>{
     $("#loan-check-name").textContent=student?.selected?"Aluno: "+student.selected.name:"Selecione um aluno";
     $("#loan-check-book").textContent=copy?.selected?"Livro: "+copy.selected.title+" ("+copy.selected.code+")":"Selecione um livro";
   };
   student=bindPicker(form,"student",activeStudents,x=>x.name,x=>x.registration,update);
   copy=bindPicker(form,"copy",ready,x=>x.title,x=>x.code,update);
   if(extra?.student_id){const x=activeStudents.find(x=>x.id===extra.student_id);if(x)student.choose(x);}
   if(extra?.book_id){const x=ready.find(x=>x.book_id===extra.book_id);if(x)copy.choose(x);}
   if(!student.selected)student.search.focus();
  }
 else if(type==="reservation"){
   const [students,books]=await Promise.all([getItems("/students?limit=1000"),getItems("/books?limit=1000")]);
   const active=students.filter(x=>x.active);
   if(!active.length||!books.length)return toast("Cadastre alunos e livros antes de reservar.",true);
   const fields='<div class="loan-ui wide"><div class="loan-two">'+
       pickerHtml("student","1  Para qual aluno?","Busque pelo nome ou matrícula")+
       pickerHtml("book","2  Qual livro?","Busque pelo título ou autor")+
       '</div></div>';
   openDialog("Nova reserva","Encontre o aluno e o livro que ele deseja reservar.",fields,async b=>{
     if(!b.student_id||!b.book_id)throw Error("Selecione um aluno e um livro nas sugestões.");
     await api("/reservations",{method:"POST",body:JSON.stringify({student_id:b.student_id,book_id:b.book_id})});
   },"Criar reserva");
   dialog.classList.add("dialog-loan");
   dialog.addEventListener("close",()=>dialog.classList.remove("dialog-loan"),{once:true});
   const form=$("#modal-form");
   bindPicker(form,"student",active,x=>x.name,x=>x.registration);
   bindPicker(form,"book",books,x=>x.title,x=>x.author);
  }
 else if(type==="password"){
   const fields=field("Senha atual","current_password","Senha atual","password",true,"",true)+field("Nova senha (mínimo 12 caracteres)","new_password","Nova senha","password",true,"",true);
   openDialog("Alterar minha senha","Escolha uma senha forte que você não usa em outros serviços.",fields,async b=>api("/me/password",{method:"POST",body:JSON.stringify(b)}),"Atualizar senha");
 }
 else if(type==="profile"){
   const old=state.user;
   const fields=field("Nome completo","name","Seu nome","text",true,old?.name||"",true)+field("E-mail","email","Seu e-mail","email",true,old?.email||"",true);
   openDialog("Editar meu perfil","Atualize seus dados pessoais.",fields,async b=>{
     const d=await api("/me",{method:"PATCH",body:JSON.stringify({name:b.name,email:b.email})});
     state.user=d.user;
     $("#user-label").textContent=d.user.name.split(" ")[0]+" · "+(d.user.role==="admin"?"Admin":"Biblioteca");
     $(".profile-avatar").textContent=d.user.name.slice(0,1).toUpperCase();
   },"Salvar meus dados");
  }
 else if(type==="user"){
   if(state.user?.role!=="admin")return;
   const old=state.users.find(x=>x.id===extra);
   const fields=field("Nome","name","Nome completo","text",true,old?.name||"",true)
     +field("E-mail","email","email@escola.com","email",true,old?.email||"",true)
     +selectField("Perfil de acesso","role",[["librarian","Bibliotecária"],["admin","Administrador"]])
     +(old?selectField("Situação da conta","active",[["true","Ativo"],["false","Desativado"]]):
       field("Senha inicial (12 ou mais caracteres)","password","Crie uma senha forte","password",true,"",true));
   openDialog(old?"Editar funcionário":"Cadastrar funcionário",old?"Altere os dados e as permissões deste acesso.":"Cadastre alguém que vai trabalhar na biblioteca.",fields,async b=>{
     await api(old?"/users/"+old.id:"/users",{method:old?"PATCH":"POST",body:JSON.stringify(old?
       {name:b.name,email:b.email,role:b.role,active:b.active==="true"}:
       {name:b.name,email:b.email,role:b.role,password:b.password})});
   },old?"Salvar funcionário":"Cadastrar funcionário");
   $("#modal-form [name=role]").value=old?.role||"librarian";
   if(old)$("#modal-form [name=active]").value=String(old.active);
  }
 else if(type==="reset-user"){
   if(state.user?.role!=="admin")return;
   const old=state.users.find(x=>x.id===extra);if(!old)return;
   const fields=field("Nova senha (mínimo 12 caracteres)","password","Crie uma senha segura","password",true,"",true);
   openDialog("Redefinir senha","Defina uma nova senha para "+old.name+".",fields,async b=>{
     await api("/users/"+old.id+"/reset-password",{method:"POST",body:JSON.stringify({password:b.password})});
   },"Salvar nova senha");
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
