// BookShare V2 — entrada da aplicação Render.
// A implementação fica em bookshare-v2/src e não reutiliza o servidor antigo.
"use strict";
import("./bookshare-v2/src/server.js").catch(error => {
  console.error("Falha ao iniciar BookShare V2:", error);
  process.exitCode = 1;
});
