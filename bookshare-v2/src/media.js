import sharp from "sharp";
import { DomainError, validUuid } from "./flows.js";

const allowHosts=new Set(["covers.openlibrary.org","books.google.com","books.googleusercontent.com","images-na.ssl-images-amazon.com","m.media-amazon.com"]);
const cache=new Map();
const escapeXML=value=>String(value||"").replace(/[&<>"']/g,char=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&apos;"}[char]));
const seed=id=>[...String(id)].reduce((a,c)=>(a*33+c.charCodeAt(0))>>>0,5381);
function fallbackBook(title,id){
 const colors=[["#d2e7d8","#295c44"],["#e7dcc7","#735832"],["#d9e4ec","#34516b"],["#f0e0d7","#814b3a"]];
 const [bg,ink]=colors[seed(id)%colors.length];
 const name=escapeXML(title.length>34?title.slice(0,32)+"…":title);
 return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 280 400" role="img" aria-label="Capa ilustrativa"><rect width="280" height="400" fill="'+bg+'"/><rect x="23" y="18" width="235" height="362" rx="8" fill="#fff" opacity=".25"/><path d="M56 126h168M56 144h168" stroke="'+ink+'" stroke-width="2" opacity=".4"/><g fill="none" stroke="'+ink+'" stroke-width="6" stroke-linejoin="round" stroke-linecap="round"><path d="M82 176v102c28-15 49-13 58-8V167c-21-7-40-4-58 9zm58-9v103c9-5 30-7 58 8V176c-18-13-37-16-58-9z"/></g><text x="140" y="79" font-size="13" text-anchor="middle" font-family="Arial" font-weight="700" letter-spacing="2" fill="'+ink+'">BOOKSHARE</text><text x="140" y="320" font-size="15" font-family="Georgia,serif" fill="'+ink+'" text-anchor="middle" textLength="200" lengthAdjust="spacingAndGlyphs">'+name+'</text><text x="140" y="355" font-size="11" text-anchor="middle" font-family="Arial" fill="'+ink+'" opacity=".65">IMAGEM ILUSTRATIVA</text></svg>';
}
function avatarTeen(id){
 const colors=[["#f2dfcb","#675447","#5a8c77","#322920"],["#e9d0c5","#514943","#a8b6dc","#1f2530"],["#eed9c8","#5c433c","#ce8f7c","#4d322d"],["#d9c7ad","#634c3d","#a8c8aa","#332824"],["#dfc0a7","#583f35","#92aacb","#493d38"]];
 const [skin,outline,shirt,hair]=colors[seed(id)%colors.length];
 const variant=seed(id)%3;
 const cut=variant===0?'<path d="M70 83q4-45 50-46 51 0 54 48l-14-15q-33-23-70 3z" fill="'+hair+'"/>':
 variant===1?'<path d="M66 110q-22-70 50-74 76-5 61 73l-15-15-7-28q-36-12-63 7l-13 32z" fill="'+hair+'"/>':
 '<path d="M70 77q10-40 54-42 53 2 52 56l-15-17q-36-11-75 11l-10 23z" fill="'+hair+'"/>';
 return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 240" role="img" aria-label="Avatar ilustrativo de estudante"><rect width="240" height="240" rx="28" fill="#eef3ed"/><circle cx="120" cy="118" r="91" fill="'+shirt+'" opacity=".15"/><path d="M37 240q9-74 83-78 75 4 83 78" fill="'+shirt+'"/><path d="M99 163v25q21 16 42 0v-25" fill="'+skin+'"/><ellipse cx="120" cy="106" rx="51" ry="62" fill="'+skin+'" stroke="'+outline+'" stroke-opacity=".09" stroke-width="3"/>'+cut+'<g fill="'+outline+'"><ellipse cx="102" cy="110" rx="3.7" ry="4.2"/><ellipse cx="140" cy="110" rx="3.7" ry="4.2"/></g><path d="M110 140q11 8 22-1" fill="none" stroke="'+outline+'" stroke-width="3" stroke-linecap="round" opacity=".7"/><path d="M112 125q8 3 13 0" fill="none" stroke="'+outline+'" stroke-width="2" opacity=".3"/><path d="M73 240q7-48 47-49 40 1 47 49" fill="'+shirt+'" opacity=".85"/></svg>';
}
function sendSVG(res,svg){res.set({"Content-Type":"image/svg+xml; charset=utf-8","Cache-Control":"private,max-age=1800","X-Content-Type-Options":"nosniff"});res.send(svg)}
function sendWebp(res,data){res.set({"Content-Type":"image/webp","Cache-Control":"private,max-age=1800","X-Content-Type-Options":"nosniff"});res.send(data)}
async function remoteCover(raw){
 if(!raw)return null;
 let buffer=null;
 const data=String(raw);
 const encoded=data.match(/^data:image\/(?:png|jpe?g|webp|gif);base64,([a-z0-9+/=]+)$/i);
 if(encoded && data.length<2200000)buffer=Buffer.from(encoded[1],"base64");
 if(!buffer){
  let url;
  try{url=new URL(data)}catch{return null}
  if(url.protocol!=="https:"||!allowHosts.has(url.hostname))return null;
  try{
   const response=await fetch(url,{redirect:"error",signal:AbortSignal.timeout(4500),headers:{"Accept":"image/avif,image/webp,image/jpeg,image/png"}});
   if(!response.ok||!/^image\/(jpeg|png|webp|gif|avif)/i.test(response.headers.get("content-type")||""))return null;
   if(Number(response.headers.get("content-length"))>2500000)return null;
   buffer=Buffer.from(await response.arrayBuffer());
  }catch{return null}
 }
 if(buffer.length>2500000)return null;
 try{return await sharp(buffer,{limitInputPixels:12000000}).rotate().resize(560,800,{fit:"inside",withoutEnlargement:true}).webp({quality:80}).toBuffer()}
 catch{return null}
}
const wrap=handler=>(req,res,next)=>Promise.resolve(handler(req,res)).catch(next);
export function registerMediaRoutes(app,{query}){
 app.get("/api/books/:id/cover",wrap(async(req,res)=>{
  const id=validUuid(req.params.id);
  const books=await query("SELECT title,cover_id,cover_url FROM bookshare_v2.books WHERE id=$1 AND school_id=$2",[id,req.schoolId]);
  if(!books.length)throw new DomainError("Livro não encontrado.",404);
  const book=books[0];
  if(book.cover_id){
   const image=await query("SELECT data FROM bookshare_v2.media_assets WHERE id=$1 AND school_id=$2",[book.cover_id,req.schoolId]);
   if(image.length)return sendWebp(res,image[0].data);
  }
  const cacheKey=req.schoolId+":"+id;
  const cached=cache.get(cacheKey);
  if(cached && cached.expires>Date.now()){
   return cached.data?sendWebp(res,cached.data):sendSVG(res,fallbackBook(book.title,id));
  }
  const cover=await remoteCover(book.cover_url);
  if(cache.size>150)cache.clear();
  cache.set(cacheKey,{data:cover,expires:Date.now()+(cover?86400000:3600000)});
  return cover?sendWebp(res,cover):sendSVG(res,fallbackBook(book.title,id));
 }));
 app.get("/api/students/:id/avatar",wrap(async(req,res)=>{
  const id=validUuid(req.params.id);
  const rows=await query("SELECT photo_id FROM bookshare_v2.students WHERE id=$1 AND school_id=$2",[id,req.schoolId]);
  if(!rows.length)throw new DomainError("Aluno não encontrado.",404);
  if(rows[0].photo_id){
   const found=await query("SELECT data FROM bookshare_v2.media_assets WHERE id=$1 AND school_id=$2",[rows[0].photo_id,req.schoolId]);
   if(found.length)return sendWebp(res,found[0].data);
  }
  return sendSVG(res,avatarTeen(id));
 }));
}
