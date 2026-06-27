
"use strict";

 

require("dotenv").config();

 

const express = require("express");

const cors = require("cors");

const helmet = require("helmet");

const rateLimit = require("express-rate-limit");

const jwt = require("jsonwebtoken");

const bcrypt = require("bcryptjs");

const crypto = require("crypto");

const sharp = require("sharp");

const { Pool } = require("pg");

 

const app = express();

const PORT = Number(process.env.PORT || 3000);

const JWT_SECRET = String(process.env.JWT_SECRET || "");

const NODE_ENV = process.env.NODE_ENV || "development";

const bookCoverCache = new Map();

const GOOGLE_BOOKS_API_KEY = String(process.env.GOOGLE_BOOKS_API_KEY || "").trim();

const bookCoverSyncState = {

  running: false,

  total: 0,

  processed: 0,

  updated: 0,

  failed: 0,

  startedAt: null,

  finishedAt: null

};

 

const PERMANENT_COVER_CANDIDATES = new Map(

  Object.entries({

  "Dom Casmurro": [

    "https://books.google.com/books/content?id=qmE0EQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=qmE0EQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=qmE0EQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Memórias Póstumas de Brás Cubas": [

    "https://books.google.com/books/content?id=qnyeEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=qnyeEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=qnyeEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "O Cortiço": [

    "https://books.google.com/books/content?id=vQMREQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=vQMREQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=vQMREQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Vidas Secas": [

    "https://books.google.com/books/content?id=OiNgEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=OiNgEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=OiNgEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Capitães da Areia": [

    "https://books.google.com/books/content?id=FDJ1_r4MCIEC&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=FDJ1_r4MCIEC&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=FDJ1_r4MCIEC&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Crime e Castigo": [

    "https://books.google.com/books/content?id=nO2MDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=nO2MDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=nO2MDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Os Irmãos Karamázov": [

    "https://books.google.com/books/content?id=8PIuEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=8PIuEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=8PIuEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Guerra e Paz": [

    "https://books.google.com/books/content?id=P1Q6DwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=P1Q6DwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=P1Q6DwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Anna Kariênina": [

    "https://books.google.com/books/content?id=vitqBgAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=vitqBgAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=vitqBgAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "O Mestre e Margarida": [

    "https://books.google.com/books/content?id=XU5HEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=XU5HEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=XU5HEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "O Pequeno Príncipe": [

    "https://books.google.com/books/content?id=_NTSEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=_NTSEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=_NTSEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Alice no País das Maravilhas": [

    "https://books.google.com/books/content?id=X5K1EAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=X5K1EAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=X5K1EAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "As Aventuras de Tom Sawyer": [

    "https://books.google.com/books/content?id=nBg5EAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=nBg5EAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=nBg5EAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "O Mágico de Oz": [

    "https://books.google.com/books/content?id=59IJ34ms1HQC&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=59IJ34ms1HQC&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=59IJ34ms1HQC&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "A Ilha do Tesouro": [

    "https://books.google.com/books/content?id=B9wXEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=B9wXEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=B9wXEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Alguma Poesia": [

    "https://covers.openlibrary.org/b/isbn/9786555874617-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9786555874617&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9786555874617.01.LZZZZZZZ.jpg"

  ],

  "Mensagem": [

    "https://books.google.com/books/content?id=0yyBEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=0yyBEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=0yyBEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Antologia Poética": [

    "https://books.google.com/books/content?id=0BFXAAAAYAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=0BFXAAAAYAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=0BFXAAAAYAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Romanceiro da Inconfidência": [

    "https://books.google.com/books/content?id=POGGDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=POGGDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=POGGDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Os Lusíadas": [

    "https://books.google.com/books/content?id=19JjCAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=19JjCAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=19JjCAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Laços de Família": [

    "https://books.google.com/books/content?id=ZxlOA83HZM0C&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=ZxlOA83HZM0C&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=ZxlOA83HZM0C&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Morangos Mofados": [

    "https://books.google.com/books/content?id=BwyvDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=BwyvDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=BwyvDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Contos Novos": [

    "https://books.google.com/books/content?id=kxD9EAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=kxD9EAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=kxD9EAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Primeiras Estórias": [

    "https://books.google.com/books/content?id=ZH5rDQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=ZH5rDQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=ZH5rDQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "O Alienista": [

    "https://books.google.com/books/content?id=TTUFEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=TTUFEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=TTUFEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Cosmos": [

    "https://books.google.com/books/content?id=Cl06FjKX6doC&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=Cl06FjKX6doC&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=Cl06FjKX6doC&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "O Mundo Assombrado pelos Demônios": [

    "https://books.google.com/books/content?id=D-tKAgAACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=D-tKAgAACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=D-tKAgAACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "A Origem das Espécies": [

    "https://books.google.com/books/content?id=a4cgEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=a4cgEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=a4cgEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Primavera Silenciosa": [

    "https://books.google.com/books/content?id=PV3pDAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=PV3pDAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=PV3pDAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Breves Respostas para Grandes Questões": [

    "https://books.google.com/books/content?id=tI9yDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=tI9yDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=tI9yDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "O Gene Egoísta": [

    "https://books.google.com/books/content?id=GA0v1URr4_QC&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=GA0v1URr4_QC&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=GA0v1URr4_QC&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "A Dupla Hélice": [

    "https://covers.openlibrary.org/b/isbn/9788537811740-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788537811740&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788537811740.01.LZZZZZZZ.jpg"

  ],

  "O Imperador de Todos os Males": [

    "https://covers.openlibrary.org/b/isbn/9788535920062-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788535920062&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788535920062.01.LZZZZZZZ.jpg"

  ],

  "A Vida Maravilhosa": [

    "https://covers.openlibrary.org/b/isbn/9788571641419-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788571641419&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788571641419.01.LZZZZZZZ.jpg"

  ],

  "A Canção da Célula": [

    "https://covers.openlibrary.org/b/isbn/9788535934724-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788535934724&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788535934724.01.LZZZZZZZ.jpg"

  ],

  "Uma Breve História do Tempo": [

    "https://books.google.com/books/content?id=igLOOwAACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=igLOOwAACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=igLOOwAACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Seis Peças Fáceis": [

    "https://covers.openlibrary.org/b/isbn/9788500004797-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788500004797&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788500004797.01.LZZZZZZZ.jpg"

  ],

  "O Universo Numa Casca de Noz": [

    "https://books.google.com/books/content?id=NXxVCwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=NXxVCwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=NXxVCwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Sete Breves Lições de Física": [

    "https://books.google.com/books/content?id=BD0qDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=BD0qDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=BD0qDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Física do Impossível": [

    "https://covers.openlibrary.org/b/isbn/9788532525598-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788532525598&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788532525598.01.LZZZZZZZ.jpg"

  ],

  "A Colher que Desaparece": [

    "https://covers.openlibrary.org/b/isbn/9788537806937-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788537806937&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788537806937.01.LZZZZZZZ.jpg"

  ],

  "Tio Tungstênio": [

    "https://covers.openlibrary.org/b/isbn/9788535919820-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788535919820&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788535919820.01.LZZZZZZZ.jpg"

  ],

  "Os Botões de Napoleão": [

    "https://covers.openlibrary.org/b/isbn/9788571109247-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788571109247&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788571109247.01.LZZZZZZZ.jpg"

  ],

  "A Tabela Periódica": [

    "https://covers.openlibrary.org/b/isbn/9788535941975-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788535941975&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788535941975.01.LZZZZZZZ.jpg"

  ],

  "O Homem que Calculava": [

    "https://covers.openlibrary.org/b/isbn/9786555875911-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9786555875911&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9786555875911.01.LZZZZZZZ.jpg"

  ],

  "O Último Teorema de Fermat": [

    "https://covers.openlibrary.org/b/isbn/9788501923790-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788501923790&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788501923790.01.LZZZZZZZ.jpg"

  ],

  "O Diabo dos Números": [

    "https://covers.openlibrary.org/b/isbn/9788571647183-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788571647183&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788571647183.01.LZZZZZZZ.jpg"

  ],

  "Alex no País dos Números": [

    "https://covers.openlibrary.org/b/isbn/9788535918380-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788535918380&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788535918380.01.LZZZZZZZ.jpg"

  ],

  "A Música dos Números Primos": [

    "https://covers.openlibrary.org/b/isbn/9788537800379-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788537800379&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788537800379.01.LZZZZZZZ.jpg"

  ],

  "1808": [

    "https://covers.openlibrary.org/b/isbn/9788576653202-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788576653202&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788576653202.01.LZZZZZZZ.jpg"

  ],

  "1822": [

    "https://covers.openlibrary.org/b/isbn/9788525060648-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788525060648&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788525060648.01.LZZZZZZZ.jpg"

  ],

  "Brasil: Uma Biografia": [

    "https://covers.openlibrary.org/b/isbn/9788535925661-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788535925661&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788535925661.01.LZZZZZZZ.jpg"

  ],

  "Sapiens": [

    "https://covers.openlibrary.org/b/isbn/9786559213016-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9786559213016&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9786559213016.01.LZZZZZZZ.jpg"

  ],

  "A Era dos Extremos": [

    "https://covers.openlibrary.org/b/isbn/9788571644687-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788571644687&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788571644687.01.LZZZZZZZ.jpg"

  ],

  "Por uma Outra Globalização": [

    "https://covers.openlibrary.org/b/isbn/9786555871869-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9786555871869&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9786555871869.01.LZZZZZZZ.jpg"

  ],

  "Geografia da Fome": [

    "https://covers.openlibrary.org/b/isbn/9786556923390-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9786556923390&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9786556923390.01.LZZZZZZZ.jpg"

  ],

  "Prisioneiros da Geografia": [

    "https://covers.openlibrary.org/b/isbn/9788537817575-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788537817575&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788537817575.01.LZZZZZZZ.jpg"

  ],

  "Armas, Germes e Aço": [

    "https://covers.openlibrary.org/b/isbn/9788501110015-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788501110015&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788501110015.01.LZZZZZZZ.jpg"

  ],

  "O Poder da Geografia": [

    "https://covers.openlibrary.org/b/isbn/9786559790678-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9786559790678&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9786559790678.01.LZZZZZZZ.jpg"

  ],

  "A República": [

    "https://books.google.com/books/content?id=38n-zwEACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=38n-zwEACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=38n-zwEACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Ética a Nicômaco": [

    "https://covers.openlibrary.org/b/isbn/9788572838818-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788572838818&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788572838818.01.LZZZZZZZ.jpg"

  ],

  "Discurso do Método": [

    "https://covers.openlibrary.org/b/isbn/9788525410979-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788525410979&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788525410979.01.LZZZZZZZ.jpg"

  ],

  "O Mundo de Sofia": [

    "https://covers.openlibrary.org/b/isbn/9788535921892-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788535921892&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788535921892.01.LZZZZZZZ.jpg"

  ],

  "Assim Falou Zaratustra": [

    "https://covers.openlibrary.org/b/isbn/9788535930481-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788535930481&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788535930481.01.LZZZZZZZ.jpg"

  ],

  "A Ética Protestante e o Espírito do Capitalismo": [

    "https://covers.openlibrary.org/b/isbn/9788572329750-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788572329750&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788572329750.01.LZZZZZZZ.jpg"

  ],

  "As Regras do Método Sociológico": [

    "https://covers.openlibrary.org/b/isbn/9788572838061-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788572838061&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788572838061.01.LZZZZZZZ.jpg"

  ],

  "Casa-Grande & Senzala": [

    "https://covers.openlibrary.org/b/isbn/9788526008694-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788526008694&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788526008694.01.LZZZZZZZ.jpg"

  ],

  "Modernidade Líquida": [

    "https://covers.openlibrary.org/b/isbn/9788571105980-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788571105980&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788571105980.01.LZZZZZZZ.jpg"

  ],

  "O Manifesto Comunista": [

    "https://covers.openlibrary.org/b/isbn/9788563560360-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788563560360&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788563560360.01.LZZZZZZZ.jpg"

  ],

  "A História da Arte": [

    "https://covers.openlibrary.org/b/isbn/9788521611851-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788521611851&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788521611851.01.LZZZZZZZ.jpg"

  ],

  "Modos de Ver": [

    "https://covers.openlibrary.org/b/isbn/9786589733997-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9786589733997&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9786589733997.01.LZZZZZZZ.jpg"

  ],

  "O Que É Arte?": [

    "https://covers.openlibrary.org/b/isbn/9788511010466-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788511010466&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788511010466.01.LZZZZZZZ.jpg"

  ],

  "Poética": [

    "https://covers.openlibrary.org/b/isbn/9788573266054-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788573266054&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788573266054.01.LZZZZZZZ.jpg"

  ],

  "A Câmara Clara": [

    "https://covers.openlibrary.org/b/isbn/9788520942680-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788520942680&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788520942680.01.LZZZZZZZ.jpg"

  ],

  "Os Inovadores": [

    "https://covers.openlibrary.org/b/isbn/9786555601367-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9786555601367&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9786555601367.01.LZZZZZZZ.jpg"

  ],

  "Código": [

    "https://covers.openlibrary.org/b/isbn/9788582606315-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788582606315&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788582606315.01.LZZZZZZZ.jpg"

  ],

  "Código Limpo": [

    "https://covers.openlibrary.org/b/isbn/9788576082675-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788576082675&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788576082675.01.LZZZZZZZ.jpg"

  ],

  "Algoritmos": [

    "https://covers.openlibrary.org/b/isbn/9788535236996-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788535236996&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788535236996.01.LZZZZZZZ.jpg"

  ],

  "Inteligência Artificial: Uma Abordagem Moderna": [

    "https://covers.openlibrary.org/b/isbn/9788595158870-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788595158870&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788595158870.01.LZZZZZZZ.jpg"

  ],

  "O Diário de Anne Frank": [

    "https://covers.openlibrary.org/b/isbn/9788501044457-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788501044457&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788501044457.01.LZZZZZZZ.jpg"

  ],

  "Longa Caminhada até a Liberdade": [

    "https://covers.openlibrary.org/b/isbn/9786555200737-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9786555200737&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9786555200737.01.LZZZZZZZ.jpg"

  ],

  "Steve Jobs": [

    "https://covers.openlibrary.org/b/isbn/9788535919714-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788535919714&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788535919714.01.LZZZZZZZ.jpg"

  ],

  "Minha História": [

    "https://covers.openlibrary.org/b/isbn/9788547000646-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788547000646&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788547000646.01.LZZZZZZZ.jpg"

  ],

  "Eu Sou Malala": [

    "https://covers.openlibrary.org/b/isbn/9788535923438-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788535923438&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788535923438.01.LZZZZZZZ.jpg"

  ],

  "Maus": [

    "https://covers.openlibrary.org/b/isbn/9788535906288-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788535906288&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788535906288.01.LZZZZZZZ.jpg"

  ],

  "Persépolis": [

    "https://covers.openlibrary.org/b/isbn/9788535911626-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788535911626&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788535911626.01.LZZZZZZZ.jpg"

  ],

  "Watchmen": [

    "https://books.google.com/books/content?id=QkK2oAEACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=QkK2oAEACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=QkK2oAEACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Turma da Mônica: Laços": [

    "https://covers.openlibrary.org/b/isbn/9788565484572-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788565484572&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788565484572.01.LZZZZZZZ.jpg"

  ],

  "Daytripper": [

    "https://covers.openlibrary.org/b/isbn/9788573517712-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788573517712&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788573517712.01.LZZZZZZZ.jpg"

  ]

})

    .map(([title, urls]) => [normalizeSearchText(title), urls])

);

 

const coverPlaceholderHashes = new Set();

 

 

 

const OFFICIAL_EDITIONS = new Map(Object.entries({

  "Dom Casmurro": {

    "title": "Dom Casmurro",

    "author": "Machado de Assis",

    "isbn13": null,

    "googleVolumeId": "qmE0EQAAQBAJ"

  },

  "Memórias Póstumas de Brás Cubas": {

    "title": "Memórias Póstumas de Brás Cubas",

    "author": "Machado de Assis",

    "isbn13": null,

    "googleVolumeId": "qnyeEAAAQBAJ"

  },

  "O Cortiço": {

    "title": "O Cortiço",

    "author": "Aluísio Azevedo",

    "isbn13": null,

    "googleVolumeId": "vQMREQAAQBAJ"

  },

  "Vidas Secas": {

    "title": "Vidas Secas",

    "author": "Graciliano Ramos",

    "isbn13": null,

    "googleVolumeId": "OiNgEQAAQBAJ"

  },

  "Capitães da Areia": {

    "title": "Capitães da Areia",

    "author": "Jorge Amado",

    "isbn13": null,

    "googleVolumeId": "FDJ1_r4MCIEC"

  },

  "Crime e Castigo": {

    "title": "Crime e Castigo",

    "author": "Fiódor Dostoiévski",

    "isbn13": null,

    "googleVolumeId": "nO2MDwAAQBAJ"

  },

  "Os Irmãos Karamázov": {

    "title": "Os Irmãos Karamázov",

    "author": "Fiódor Dostoiévski",

    "isbn13": null,

    "googleVolumeId": "8PIuEAAAQBAJ"

  },

  "Guerra e Paz": {

    "title": "Guerra e Paz",

    "author": "Liev Tolstói",

    "isbn13": null,

    "googleVolumeId": "P1Q6DwAAQBAJ"

  },

  "Anna Kariênina": {

    "title": "Anna Kariênina",

    "author": "Liev Tolstói",

    "isbn13": null,

    "googleVolumeId": "vitqBgAAQBAJ"

  },

  "O Mestre e Margarida": {

    "title": "O Mestre e Margarida",

    "author": "Mikhail Bulgákov",

    "isbn13": null,

    "googleVolumeId": "XU5HEQAAQBAJ"

  },

  "O Pequeno Príncipe": {

    "title": "O Pequeno Príncipe",

    "author": "Antoine de Saint-Exupéry",

    "isbn13": null,

    "googleVolumeId": "_NTSEAAAQBAJ"

  },

  "Alice no País das Maravilhas": {

    "title": "Alice no País das Maravilhas",

    "author": "Lewis Carroll",

    "isbn13": null,

    "googleVolumeId": "X5K1EAAAQBAJ"

  },

  "As Aventuras de Tom Sawyer": {

    "title": "As Aventuras de Tom Sawyer",

    "author": "Mark Twain",

    "isbn13": null,

    "googleVolumeId": "nBg5EAAAQBAJ"

  },

  "O Mágico de Oz": {

    "title": "O Mágico de Oz",

    "author": "L. Frank Baum",

    "isbn13": null,

    "googleVolumeId": "59IJ34ms1HQC"

  },

  "A Ilha do Tesouro": {

    "title": "A Ilha do Tesouro",

    "author": "Robert Louis Stevenson",

    "isbn13": null,

    "googleVolumeId": "B9wXEAAAQBAJ"

  },

  "Alguma Poesia": {

    "title": "Alguma Poesia",

    "author": "Carlos Drummond de Andrade",

    "isbn13": "9786555874617",

    "googleVolumeId": null

  },

  "Mensagem": {

    "title": "Mensagem",

    "author": "Fernando Pessoa",

    "isbn13": null,

    "googleVolumeId": "0yyBEQAAQBAJ"

  },

  "Antologia Poética": {

    "title": "Antologia Poética",

    "author": "Vinicius de Moraes",

    "isbn13": null,

    "googleVolumeId": "0BFXAAAAYAAJ"

  },

  "Romanceiro da Inconfidência": {

    "title": "Romanceiro da Inconfidência",

    "author": "Cecília Meireles",

    "isbn13": null,

    "googleVolumeId": "POGGDwAAQBAJ"

  },

  "Os Lusíadas": {

    "title": "Os Lusíadas",

    "author": "Luís de Camões",

    "isbn13": null,

    "googleVolumeId": "19JjCAAAQBAJ"

  },

  "Laços de Família": {

    "title": "Laços de Família",

    "author": "Clarice Lispector",

    "isbn13": null,

    "googleVolumeId": "ZxlOA83HZM0C"

  },

  "Morangos Mofados": {

    "title": "Morangos Mofados",

    "author": "Caio Fernando Abreu",

    "isbn13": null,

    "googleVolumeId": "BwyvDwAAQBAJ"

  },

  "Contos Novos": {

    "title": "Contos Novos",

    "author": "Mário de Andrade",

    "isbn13": null,

    "googleVolumeId": "kxD9EAAAQBAJ"

  },

  "Primeiras Estórias": {

    "title": "Primeiras Estórias",

    "author": "João Guimarães Rosa",

    "isbn13": null,

    "googleVolumeId": "ZH5rDQAAQBAJ"

  },

  "O Alienista": {

    "title": "O Alienista",

    "author": "Machado de Assis",

    "isbn13": null,

    "googleVolumeId": "TTUFEQAAQBAJ"

  },

  "Cosmos": {

    "title": "Cosmos",

    "author": "Carl Sagan",

    "isbn13": null,

    "googleVolumeId": "Cl06FjKX6doC"

  },

  "O Mundo Assombrado pelos Demônios": {

    "title": "O Mundo Assombrado pelos Demônios",

    "author": "Carl Sagan",

    "isbn13": null,

    "googleVolumeId": "D-tKAgAACAAJ"

  },

  "A Origem das Espécies": {

    "title": "A Origem das Espécies",

    "author": "Charles Darwin",

    "isbn13": null,

    "googleVolumeId": "a4cgEQAAQBAJ"

  },

  "Primavera Silenciosa": {

    "title": "Primavera Silenciosa",

    "author": "Rachel Carson",

    "isbn13": null,

    "googleVolumeId": "PV3pDAAAQBAJ"

  },

  "Breves Respostas para Grandes Questões": {

    "title": "Breves Respostas para Grandes Questões",

    "author": "Stephen Hawking",

    "isbn13": null,

    "googleVolumeId": "tI9yDwAAQBAJ"

  },

  "O Gene Egoísta": {

    "title": "O Gene Egoísta",

    "author": "Richard Dawkins",

    "isbn13": null,

    "googleVolumeId": "GA0v1URr4_QC"

  },

  "A Dupla Hélice": {

    "title": "A Dupla Hélice",

    "author": "James D. Watson",

    "isbn13": "9788537811740",

    "googleVolumeId": null

  },

  "O Imperador de Todos os Males": {

    "title": "O Imperador de Todos os Males",

    "author": "Siddhartha Mukherjee",

    "isbn13": "9788535920062",

    "googleVolumeId": null

  },

  "A Vida Maravilhosa": {

    "title": "A Vida Maravilhosa",

    "author": "Stephen Jay Gould",

    "isbn13": "9788571641419",

    "googleVolumeId": null

  },

  "A Canção da Célula": {

    "title": "A Canção da Célula",

    "author": "Siddhartha Mukherjee",

    "isbn13": "9788535934724",

    "googleVolumeId": null

  },

  "Uma Breve História do Tempo": {

    "title": "Uma Breve História do Tempo",

    "author": "Stephen Hawking",

    "isbn13": null,

    "googleVolumeId": "igLOOwAACAAJ"

  },

  "Seis Peças Fáceis": {

    "title": "Seis Peças Fáceis",

    "author": "Richard Feynman",

    "isbn13": "9788500004797",

    "googleVolumeId": null

  },

  "O Universo Numa Casca de Noz": {

    "title": "O Universo Numa Casca de Noz",

    "author": "Stephen Hawking",

    "isbn13": null,

    "googleVolumeId": "NXxVCwAAQBAJ"

  },

  "Sete Breves Lições de Física": {

    "title": "Sete Breves Lições de Física",

    "author": "Carlo Rovelli",

    "isbn13": null,

    "googleVolumeId": "BD0qDwAAQBAJ"

  },

  "Física do Impossível": {

    "title": "Física do Impossível",

    "author": "Michio Kaku",

    "isbn13": "9788532525598",

    "googleVolumeId": null

  },

  "A Colher que Desaparece": {

    "title": "A Colher que Desaparece",

    "author": "Sam Kean",

    "isbn13": "9788537806937",

    "googleVolumeId": null

  },

  "Tio Tungstênio": {

    "title": "Tio Tungstênio",

    "author": "Oliver Sacks",

    "isbn13": "9788535919820",

    "googleVolumeId": null

  },

  "Os Botões de Napoleão": {

    "title": "Os Botões de Napoleão",

    "author": "Penny Le Couteur e Jay Burreson",

    "isbn13": "9788571109247",

    "googleVolumeId": null

  },

  "A Tabela Periódica": {

    "title": "A Tabela Periódica",

    "author": "Primo Levi",

    "isbn13": "9788535941975",

    "googleVolumeId": null

  },

  "O Homem que Calculava": {

    "title": "O Homem que Calculava",

    "author": "Malba Tahan",

    "isbn13": "9786555875911",

    "googleVolumeId": null

  },

  "O Último Teorema de Fermat": {

    "title": "O Último Teorema de Fermat",

    "author": "Simon Singh",

    "isbn13": "9788501923790",

    "googleVolumeId": null

  },

  "O Diabo dos Números": {

    "title": "O Diabo dos Números",

    "author": "Hans Magnus Enzensberger",

    "isbn13": "9788571647183",

    "googleVolumeId": null

  },

  "Alex no País dos Números": {

    "title": "Alex no País dos Números",

    "author": "Alex Bellos",

    "isbn13": "9788535918380",

    "googleVolumeId": null

  },

  "A Música dos Números Primos": {

    "title": "A Música dos Números Primos",

    "author": "Marcus du Sautoy",

    "isbn13": "9788537800379",

    "googleVolumeId": null

  },

  "1808": {

    "title": "1808",

    "author": "Laurentino Gomes",

    "isbn13": "9788576653202",

    "googleVolumeId": null

  },

  "1822": {

    "title": "1822",

    "author": "Laurentino Gomes",

    "isbn13": "9788525060648",

    "googleVolumeId": null

  },

  "Brasil: Uma Biografia": {

    "title": "Brasil: Uma Biografia",

    "author": "Lilia Schwarcz e Heloisa Starling",

    "isbn13": "9788535925661",

    "googleVolumeId": null

  },

  "Sapiens": {

    "title": "Sapiens",

    "author": "Yuval Noah Harari",

    "isbn13": "9786559213016",

    "googleVolumeId": null

  },

  "A Era dos Extremos": {

    "title": "A Era dos Extremos",

    "author": "Eric Hobsbawm",

    "isbn13": "9788571644687",

    "googleVolumeId": null

  },

  "Por uma Outra Globalização": {

    "title": "Por uma Outra Globalização",

    "author": "Milton Santos",

    "isbn13": "9786555871869",

    "googleVolumeId": null

  },

  "Geografia da Fome": {

    "title": "Geografia da Fome",

    "author": "Josué de Castro",

    "isbn13": "9786556923390",

    "googleVolumeId": null

  },

  "Prisioneiros da Geografia": {

    "title": "Prisioneiros da Geografia",

    "author": "Tim Marshall",

    "isbn13": "9788537817575",

    "googleVolumeId": null

  },

  "Armas, Germes e Aço": {

    "title": "Armas, Germes e Aço",

    "author": "Jared Diamond",

    "isbn13": "9788501110015",

    "googleVolumeId": null

  },

  "O Poder da Geografia": {

    "title": "O Poder da Geografia",

    "author": "Tim Marshall",

    "isbn13": "9786559790678",

    "googleVolumeId": null

  },

  "A República": {

    "title": "A República",

    "author": "Platão",

    "isbn13": null,

    "googleVolumeId": "38n-zwEACAAJ"

  },

  "Ética a Nicômaco": {

    "title": "Ética a Nicômaco",

    "author": "Aristóteles",

    "isbn13": "9788572838818",

    "googleVolumeId": null

  },

  "Discurso do Método": {

    "title": "Discurso do Método",

    "author": "René Descartes",

    "isbn13": "9788525410979",

    "googleVolumeId": null

  },

  "O Mundo de Sofia": {

    "title": "O Mundo de Sofia",

    "author": "Jostein Gaarder",

    "isbn13": "9788535921892",

    "googleVolumeId": null

  },

  "Assim Falou Zaratustra": {

    "title": "Assim Falou Zaratustra",

    "author": "Friedrich Nietzsche",

    "isbn13": "9788535930481",

    "googleVolumeId": null

  },

  "A Ética Protestante e o Espírito do Capitalismo": {

    "title": "A Ética Protestante e o Espírito do Capitalismo",

    "author": "Max Weber",

    "isbn13": "9788572329750",

    "googleVolumeId": null

  },

  "As Regras do Método Sociológico": {

    "title": "As Regras do Método Sociológico",

    "author": "Émile Durkheim",

    "isbn13": "9788572838061",

    "googleVolumeId": null

  },

  "Casa-Grande & Senzala": {

    "title": "Casa-Grande & Senzala",

    "author": "Gilberto Freyre",

    "isbn13": "9788526008694",

    "googleVolumeId": null

  },

  "Modernidade Líquida": {

    "title": "Modernidade Líquida",

    "author": "Zygmunt Bauman",

    "isbn13": "9788571105980",

    "googleVolumeId": null

  },

  "O Manifesto Comunista": {

    "title": "O Manifesto Comunista",

    "author": "Karl Marx e Friedrich Engels",

    "isbn13": "9788563560360",

    "googleVolumeId": null

  },

  "A História da Arte": {

    "title": "A História da Arte",

    "author": "E. H. Gombrich",

    "isbn13": "9788521611851",

    "googleVolumeId": null

  },

  "Modos de Ver": {

    "title": "Modos de Ver",

    "author": "John Berger",

    "isbn13": "9786589733997",

    "googleVolumeId": null

  },

  "O Que É Arte?": {

    "title": "O Que É Arte?",

    "author": "Jorge Coli",

    "isbn13": "9788511010466",

    "googleVolumeId": null

  },

  "Poética": {

    "title": "Poética",

    "author": "Aristóteles",

    "isbn13": "9788573266054",

    "googleVolumeId": null

  },

  "A Câmara Clara": {

    "title": "A Câmara Clara",

    "author": "Roland Barthes",

    "isbn13": "9788520942680",

    "googleVolumeId": null

  },

  "Os Inovadores": {

    "title": "Os Inovadores",

    "author": "Walter Isaacson",

    "isbn13": "9786555601367",

    "googleVolumeId": null

  },

  "Código": {

    "title": "Código",

    "author": "Charles Petzold",

    "isbn13": "9788582606315",

    "googleVolumeId": null

  },

  "Código Limpo": {

    "title": "Código Limpo",

    "author": "Robert C. Martin",

    "isbn13": "9788576082675",

    "googleVolumeId": null

  },

  "Algoritmos": {

    "title": "Algoritmos",

    "author": "Thomas Cormen e colaboradores",

    "isbn13": "9788535236996",

    "googleVolumeId": null

  },

  "Inteligência Artificial: Uma Abordagem Moderna": {

    "title": "Inteligência Artificial: Uma Abordagem Moderna",

    "author": "Stuart Russell e Peter Norvig",

    "isbn13": "9788595158870",

    "googleVolumeId": null

  },

  "O Diário de Anne Frank": {

    "title": "O Diário de Anne Frank",

    "author": "Anne Frank",

    "isbn13": "9788501044457",

    "googleVolumeId": null

  },

  "Longa Caminhada até a Liberdade": {

    "title": "Longa Caminhada até a Liberdade",

    "author": "Nelson Mandela",

    "isbn13": "9786555200737",

    "googleVolumeId": null

  },

  "Steve Jobs": {

    "title": "Steve Jobs",

    "author": "Walter Isaacson",

    "isbn13": "9788535919714",

    "googleVolumeId": null

  },

  "Minha História": {

    "title": "Minha História",

    "author": "Michelle Obama",

    "isbn13": "9788547000646",

    "googleVolumeId": null

  },

  "Eu Sou Malala": {

    "title": "Eu Sou Malala",

    "author": "Malala Yousafzai",

    "isbn13": "9788535923438",

    "googleVolumeId": null

  },

  "Maus": {

    "title": "Maus",

    "author": "Art Spiegelman",

    "isbn13": "9788535906288",

    "googleVolumeId": null

  },

  "Persépolis": {

    "title": "Persépolis",

    "author": "Marjane Satrapi",

    "isbn13": "9788535911626",

    "googleVolumeId": null

  },

  "Watchmen": {

    "title": "Watchmen",

    "author": "Alan Moore e Dave Gibbons",

    "isbn13": null,

    "googleVolumeId": "QkK2oAEACAAJ"

  },

  "Turma da Mônica: Laços": {

    "title": "Turma da Mônica: Laços",

    "author": "Vitor e Lu Cafaggi",

    "isbn13": "9788565484572",

    "googleVolumeId": null

  },

  "Daytripper": {

    "title": "Daytripper",

    "author": "Fábio Moon e Gabriel Bá",

    "isbn13": "9788573517712",

    "googleVolumeId": null

  }

}).map(([title, edition]) => [normalizeSearchText(title), edition]));

 

 

const CATALOG_V30_EDITIONS = new Map(

  Object.entries({

    "1984": { title: "1984", author: "George Orwell", isbn13: "9788580864458", googleVolumeId: "5VD2SwmX7dAC" },

    "A Revolução dos Bichos": { title: "A Revolução dos Bichos", author: "George Orwell", isbn13: "9788596042642", googleVolumeId: "EQftEAAAQBAJ" },

    "Fahrenheit 451": { title: "Fahrenheit 451", author: "Ray Bradbury", isbn13: "9780345410016", googleVolumeId: "Ipq--vf0ZFkC" },

    "O Hobbit": { title: "O Hobbit", author: "J.R.R. Tolkien", isbn13: "9788595085800", googleVolumeId: "2LeZDwAAQBAJ" },

    "Quarto de Despejo": { title: "Quarto de Despejo", author: "Carolina Maria de Jesus", isbn13: "9788508196555", googleVolumeId: "xw0CzwEACAAJ" },

    "A Hora da Estrela": { title: "A Hora da Estrela", author: "Clarice Lispector", isbn13: "9786555950236", googleVolumeId: "82UHEAAAQBAJ" },

    "O Auto da Compadecida": { title: "O Auto da Compadecida", author: "Ariano Suassuna", isbn13: "9788520942833", googleVolumeId: "I0pWDwAAQBAJ" },

    "Torto Arado": { title: "Torto Arado", author: "Itamar Vieira Junior", isbn13: "9786580309320", googleVolumeId: "CdOiDwAAQBAJ" },

    "Frankenstein": { title: "Frankenstein", author: "Mary Shelley", isbn13: "9786552942555", googleVolumeId: "DsdzEQAAQBAJ" },

    "Drácula": { title: "Drácula", author: "Bram Stoker", isbn13: "9788595201569", googleVolumeId: "XoqWEAAAQBAJ" }

  }).map(([title, edition]) => [normalizeSearchText(title), edition])

);

 

for (const edition of CATALOG_V30_EDITIONS.values()) {

  const titleKey = normalizeSearchText(edition.title);

  const candidates = [

    `https://books.google.com/books/content?id=${edition.googleVolumeId}&printsec=frontcover&img=1&zoom=3&source=gbs_api`,

    `https://books.googleusercontent.com/books/content?id=${edition.googleVolumeId}&printsec=frontcover&img=1&zoom=3&source=gbs_api`,

    `https://books.google.com/books/publisher/content?id=${edition.googleVolumeId}&printsec=frontcover&img=1&zoom=3&source=gbs_api`,

    `https://covers.openlibrary.org/b/isbn/${edition.isbn13}-L.jpg?default=false`

  ];

 

  PERMANENT_COVER_CANDIDATES.set(titleKey, candidates);

}

 

 

const FINAL_50_REAL_COVER_CANDIDATES = new Map(

  Object.entries({

  "Dom Casmurro": [

    "https://books.google.com/books/content?id=qmE0EQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=qmE0EQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=qmE0EQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Memórias Póstumas de Brás Cubas": [

    "https://books.google.com/books/content?id=qnyeEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=qnyeEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=qnyeEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "O Cortiço": [

    "https://books.google.com/books/content?id=vQMREQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=vQMREQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=vQMREQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Vidas Secas": [

    "https://books.google.com/books/content?id=OiNgEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=OiNgEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=OiNgEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Capitães da Areia": [

    "https://books.google.com/books/content?id=FDJ1_r4MCIEC&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=FDJ1_r4MCIEC&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=FDJ1_r4MCIEC&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Crime e Castigo": [

    "https://books.google.com/books/content?id=nO2MDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=nO2MDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=nO2MDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Os Irmãos Karamázov": [

    "https://books.google.com/books/content?id=8PIuEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=8PIuEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=8PIuEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Guerra e Paz": [

    "https://books.google.com/books/content?id=P1Q6DwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=P1Q6DwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=P1Q6DwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Anna Kariênina": [

    "https://books.google.com/books/content?id=vitqBgAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=vitqBgAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=vitqBgAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "O Mestre e Margarida": [

    "https://books.google.com/books/content?id=XU5HEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=XU5HEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=XU5HEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "O Pequeno Príncipe": [

    "https://books.google.com/books/content?id=_NTSEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=_NTSEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=_NTSEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Alice no País das Maravilhas": [

    "https://books.google.com/books/content?id=X5K1EAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=X5K1EAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=X5K1EAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "As Aventuras de Tom Sawyer": [

    "https://books.google.com/books/content?id=nBg5EAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=nBg5EAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=nBg5EAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "O Mágico de Oz": [

    "https://books.google.com/books/content?id=59IJ34ms1HQC&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=59IJ34ms1HQC&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=59IJ34ms1HQC&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "A Ilha do Tesouro": [

    "https://books.google.com/books/content?id=B9wXEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=B9wXEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=B9wXEAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Mensagem": [

    "https://books.google.com/books/content?id=0yyBEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=0yyBEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=0yyBEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Antologia Poética": [

    "https://books.google.com/books/content?id=0BFXAAAAYAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=0BFXAAAAYAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=0BFXAAAAYAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Romanceiro da Inconfidência": [

    "https://books.google.com/books/content?id=POGGDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=POGGDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=POGGDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Os Lusíadas": [

    "https://books.google.com/books/content?id=19JjCAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=19JjCAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=19JjCAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Laços de Família": [

    "https://books.google.com/books/content?id=ZxlOA83HZM0C&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=ZxlOA83HZM0C&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=ZxlOA83HZM0C&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Morangos Mofados": [

    "https://books.google.com/books/content?id=BwyvDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=BwyvDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=BwyvDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Contos Novos": [

    "https://books.google.com/books/content?id=kxD9EAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=kxD9EAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=kxD9EAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Primeiras Estórias": [

    "https://books.google.com/books/content?id=ZH5rDQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=ZH5rDQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=ZH5rDQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "O Alienista": [

    "https://books.google.com/books/content?id=TTUFEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=TTUFEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=TTUFEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Cosmos": [

    "https://books.google.com/books/content?id=Cl06FjKX6doC&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=Cl06FjKX6doC&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=Cl06FjKX6doC&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "O Mundo Assombrado pelos Demônios": [

    "https://books.google.com/books/content?id=D-tKAgAACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=D-tKAgAACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=D-tKAgAACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "A Origem das Espécies": [

    "https://books.google.com/books/content?id=a4cgEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=a4cgEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=a4cgEQAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Primavera Silenciosa": [

    "https://books.google.com/books/content?id=PV3pDAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=PV3pDAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=PV3pDAAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Breves Respostas para Grandes Questões": [

    "https://books.google.com/books/content?id=tI9yDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=tI9yDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=tI9yDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "O Gene Egoísta": [

    "https://books.google.com/books/content?id=GA0v1URr4_QC&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=GA0v1URr4_QC&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=GA0v1URr4_QC&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Uma Breve História do Tempo": [

    "https://books.google.com/books/content?id=igLOOwAACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=igLOOwAACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=igLOOwAACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "O Universo Numa Casca de Noz": [

    "https://books.google.com/books/content?id=NXxVCwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=NXxVCwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=NXxVCwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Sete Breves Lições de Física": [

    "https://books.google.com/books/content?id=BD0qDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=BD0qDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=BD0qDwAAQBAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "A República": [

    "https://books.google.com/books/content?id=38n-zwEACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=38n-zwEACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=38n-zwEACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "Watchmen": [

    "https://books.google.com/books/content?id=QkK2oAEACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=QkK2oAEACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=QkK2oAEACAAJ&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ],

  "1984": [

    "https://books.google.com/books/content?id=5VD2SwmX7dAC&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=5VD2SwmX7dAC&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=5VD2SwmX7dAC&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://covers.openlibrary.org/b/isbn/9788580864458-L.jpg?default=false"

  ],

  "A Revolução dos Bichos": [

    "https://books.google.com/books/content?id=EQftEAAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=EQftEAAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=EQftEAAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://covers.openlibrary.org/b/isbn/9788596042642-L.jpg?default=false"

  ],

  "Fahrenheit 451": [

    "https://books.google.com/books/content?id=Ipq--vf0ZFkC&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=Ipq--vf0ZFkC&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=Ipq--vf0ZFkC&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://covers.openlibrary.org/b/isbn/9780345410016-L.jpg?default=false"

  ],

  "O Hobbit": [

    "https://books.google.com/books/content?id=2LeZDwAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=2LeZDwAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=2LeZDwAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://covers.openlibrary.org/b/isbn/9788595085800-L.jpg?default=false"

  ],

  "Quarto de Despejo": [

    "https://books.google.com/books/content?id=xw0CzwEACAAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=xw0CzwEACAAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=xw0CzwEACAAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://covers.openlibrary.org/b/isbn/9788508196555-L.jpg?default=false"

  ],

  "A Hora da Estrela": [

    "https://books.google.com/books/content?id=82UHEAAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=82UHEAAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=82UHEAAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://covers.openlibrary.org/b/isbn/9786555950236-L.jpg?default=false"

  ],

  "O Auto da Compadecida": [

    "https://books.google.com/books/content?id=I0pWDwAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=I0pWDwAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=I0pWDwAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://covers.openlibrary.org/b/isbn/9788520942833-L.jpg?default=false"

  ],

  "Torto Arado": [

    "https://books.google.com/books/content?id=CdOiDwAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=CdOiDwAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=CdOiDwAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://covers.openlibrary.org/b/isbn/9786580309320-L.jpg?default=false"

  ],

  "Frankenstein": [

    "https://books.google.com/books/content?id=DsdzEQAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=DsdzEQAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=DsdzEQAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://covers.openlibrary.org/b/isbn/9786552942555-L.jpg?default=false"

  ],

  "Drácula": [

    "https://books.google.com/books/content?id=XoqWEAAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.googleusercontent.com/books/content?id=XoqWEAAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://books.google.com/books/publisher/content?id=XoqWEAAAQBAJ&printsec=frontcover&img=1&zoom=3&source=gbs_api",

    "https://covers.openlibrary.org/b/isbn/9788595201569-L.jpg?default=false"

  ],

  "A Canção da Célula": [

    "https://covers.openlibrary.org/b/isbn/9788535934724-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788535934724&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788535934724.01.LZZZZZZZ.jpg"

  ],

  "Seis Peças Fáceis": [

    "https://covers.openlibrary.org/b/isbn/9788500004797-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788500004797&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788500004797.01.LZZZZZZZ.jpg"

  ],

  "A Colher que Desaparece": [

    "https://covers.openlibrary.org/b/isbn/9788537806937-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788537806937&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788537806937.01.LZZZZZZZ.jpg"

  ],

  "Turma da Mônica: Laços": [

    "https://covers.openlibrary.org/b/isbn/9788565484572-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788565484572&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788565484572.01.LZZZZZZZ.jpg"

  ],

  "O Mundo de Sofia": [

    "https://covers.openlibrary.org/b/isbn/9788535921892-L.jpg?default=false",

    "https://books.google.com/books/content?vid=ISBN9788535921892&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://images-na.ssl-images-amazon.com/images/P/9788535921892.01.LZZZZZZZ.jpg"

  ]

}).map(([title, urls]) => [normalizeSearchText(title), urls])

);

for (const [titleKey, urls] of FINAL_50_REAL_COVER_CANDIDATES.entries()) {

  PERMANENT_COVER_CANDIDATES.set(titleKey, urls);

}

 

if (JWT_SECRET.length < 24) {

  console.error("JWT_SECRET ausente ou curta. Configure uma chave segura no Render.");

  process.exit(1);

}

 

if (!process.env.DATABASE_URL) {

  console.error("DATABASE_URL não configurada.");

  process.exit(1);

}

 

const pool = new Pool({

  connectionString: process.env.DATABASE_URL,

  ssl: NODE_ENV === "production" ? { rejectUnauthorized: false } : false,

  max: 15,

  idleTimeoutMillis: 30000,

  connectionTimeoutMillis: 12000,

  statement_timeout: 25000

});

 

const allowedOrigins = String(process.env.FRONTEND_URL || "")

  .split(",")

  .map(origin => origin.trim())

  .filter(Boolean);

 

function isTrustedOrigin(origin) {

  if (!origin) return true;

 

  try {

    const { hostname } = new URL(origin);

    if (allowedOrigins.includes(origin)) return true;

    if (hostname === "localhost" || hostname === "127.0.0.1") return true;

    if (hostname.endsWith(".github.io")) return true;

    if (hostname.endsWith(".onrender.com")) return true;

  } catch (_error) {

    return false;

  }

 

  return false;

}

 

app.set("trust proxy", 1);

 

app.use(helmet({

  crossOriginResourcePolicy: { policy: "cross-origin" },

  contentSecurityPolicy: false

}));

 

app.use(cors({

  origin(origin, callback) {

    if (NODE_ENV !== "production" && allowedOrigins.length === 0) return callback(null, true);

    if (isTrustedOrigin(origin)) return callback(null, true);

    return callback(new Error("Origem não autorizada pelo CORS."));

  },

  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],

  allowedHeaders: ["Content-Type", "Authorization"]

}));

 

app.use(express.json({ limit: "3mb" }));

 

app.use("/api/auth/login", rateLimit({

  windowMs: 15 * 60 * 1000,

  limit: 20,

  standardHeaders: true,

  legacyHeaders: false,

  message: { message: "Muitas tentativas de acesso. Aguarde alguns minutos." }

}));

 

app.use("/api", rateLimit({

  windowMs: 60 * 1000,

  limit: 500,

  standardHeaders: true,

  legacyHeaders: false,

  message: { message: "Muitas requisições. Aguarde um momento." }

}));

 

 

function normalizeSearchText(value) {

  return String(value || "")

    .normalize("NFD")

    .replace(/[\u0300-\u036f]/g, "")

    .toLowerCase()

    .replace(/[^a-z0-9]+/g, " ")

    .trim();

}

 

function asyncRoute(handler) {

  return (req, res, next) => Promise.resolve(handler(req, res, next)).catch(next);

}

 

function httpError(status, message) {

  const error = new Error(message);

  error.status = status;

  return error;

}

 

function cleanText(value, maxLength = null) {

  const text = String(value ?? "").trim();

  if (!text) return null;

  return maxLength ? text.slice(0, maxLength) : text;

}

 

function requiredText(value, fieldName, maxLength = null) {

  const text = cleanText(value, maxLength);

  if (!text) throw httpError(400, `Informe ${fieldName}.`);

  return text;

}

 

function cleanInteger(value, { min = null, max = null, nullable = true } = {}) {

  if (value === "" || value === null || value === undefined) {

    if (nullable) return null;

    throw httpError(400, "Informe um número válido.");

  }

 

  const number = Number(value);

  if (!Number.isInteger(number)) throw httpError(400, "Informe um número inteiro válido.");

  if (min !== null && number < min) throw httpError(400, `O valor mínimo permitido é ${min}.`);

  if (max !== null && number > max) throw httpError(400, `O valor máximo permitido é ${max}.`);

  return number;

}

 

function cleanBoolean(value, defaultValue = false) {

  if (typeof value === "boolean") return value;

  if (value === "true" || value === 1 || value === "1") return true;

  if (value === "false" || value === 0 || value === "0") return false;

  return defaultValue;

}

 

function cleanDate(value, fieldName, nullable = true) {

  if (!value) {

    if (nullable) return null;

    throw httpError(400, `Informe ${fieldName}.`);

  }

 

  const text = String(value).slice(0, 10);

  if (!/^\d{4}-\d{2}-\d{2}$/.test(text) || Number.isNaN(new Date(`${text}T00:00:00`).getTime())) {

    throw httpError(400, `${fieldName} inválida.`);

  }

  return text;

}

 

function cleanEmail(value) {

  const email = requiredText(value, "o e-mail", 180).toLowerCase();

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw httpError(400, "Informe um e-mail válido.");

  return email;

}

 

function signToken(user) {

  return jwt.sign(

    {

      sub: user.id,

      role: user.role,

      email: user.email

    },

    JWT_SECRET,

    {

      expiresIn: "12h",

      issuer: "bookshare-api",

      audience: "bookshare-frontend"

    }

  );

}

 

async function authenticate(req, res, next) {

  try {

    const header = String(req.headers.authorization || "");

    const [scheme, token] = header.split(" ");

 

    if (scheme !== "Bearer" || !token) {

      return res.status(401).json({ message: "Token de acesso não informado." });

    }

 

    const payload = jwt.verify(token, JWT_SECRET, {

      issuer: "bookshare-api",

      audience: "bookshare-frontend"

    });

 

    const result = await pool.query(

      `SELECT

         u.id,

         u.name,

         u.email,

         u.role,

         u.active,

         u.last_login_at,

         u.avatar_url,

         u.phone,

         u.job_title,

         u.school_id,

         s.name AS school_name

       FROM users u

       LEFT JOIN schools s ON s.id = u.school_id

       WHERE u.id = $1

         AND u.deleted_at IS NULL`,

      [payload.sub]

    );

 

    const user = result.rows[0];

    if (!user || !user.active) {

      return res.status(401).json({ message: "Conta inexistente ou bloqueada." });

    }

 

    req.user = user;

    next();

  } catch (error) {

    return res.status(401).json({ message: "Sessão inválida ou expirada." });

  }

}

 

function requireRole(...roles) {

  return (req, res, next) => {

    if (!req.user || !roles.includes(req.user.role)) {

      return res.status(403).json({ message: "Você não possui permissão para esta ação." });

    }

    next();

  };

}

 

async function audit(client, req, action, entityType, entityId = null, details = {}) {

  await client.query(

    `INSERT INTO audit_logs

      (user_id, action, entity_type, entity_id, details, ip_address, user_agent)

     VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7)`,

    [

      req.user?.id || null,

      action,

      entityType,

      entityId ? String(entityId) : null,

      JSON.stringify(details || {}),

      req.ip || null,

      req.headers["user-agent"] || null

    ]

  );

}

 

async function getSettings(client = pool) {

  const result = await client.query(

    `SELECT

       id,

       school_name,

       library_name,

       contact_email,

       contact_phone,

       current_school_year,

       default_loan_days,

       max_active_loans,

       max_renewals,

       renewal_days,

       due_soon_days,

       reservation_hold_days,

       block_overdue_students,

       notice_template,

       reservation_template,

       updated_at

     FROM settings

     WHERE id = 1`

  );

 

  if (!result.rows[0]) throw httpError(500, "As configurações iniciais não foram encontradas.");

  return result.rows[0];

}

 

function makeInventoryCode() {

  const date = new Date();

  const stamp = `${date.getFullYear()}${String(date.getMonth() + 1).padStart(2, "0")}${String(date.getDate()).padStart(2, "0")}`;

  return `BS-${stamp}-${crypto.randomBytes(3).toString("hex").toUpperCase()}`;

}

 

async function createInventoryCodes(client, bookId, quantity, acquiredAt = null, notes = null) {

  const copies = [];

  for (let index = 0; index < quantity; index += 1) {

    let inserted = null;

    for (let attempt = 0; attempt < 5 && !inserted; attempt += 1) {

      try {

        const result = await client.query(

          `INSERT INTO book_copies

            (book_id, inventory_code, status, acquired_at, condition_notes)

           VALUES ($1, $2, 'available', $3, $4)

           RETURNING *`,

          [bookId, makeInventoryCode(), acquiredAt, notes]

        );

        inserted = result.rows[0];

      } catch (error) {

        if (error.code !== "23505" || attempt === 4) throw error;

      }

    }

    copies.push(inserted);

  }

  return copies;

}

 

 

async function ensureRuntimeSchema() {

  const migrations = [

    `CREATE TABLE IF NOT EXISTS schools (

       id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

       name VARCHAR(140) NOT NULL,

       code VARCHAR(30) NOT NULL UNIQUE,

       address VARCHAR(220),

       contact_email VARCHAR(180),

       phone VARCHAR(40),

       active BOOLEAN NOT NULL DEFAULT TRUE,

       created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

       updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()

     )`,

    `ALTER TABLE IF EXISTS users ADD COLUMN IF NOT EXISTS avatar_url TEXT`,

    `ALTER TABLE IF EXISTS users ADD COLUMN IF NOT EXISTS school_id UUID`,

    `ALTER TABLE IF EXISTS users ADD COLUMN IF NOT EXISTS phone VARCHAR(40)`,

    `ALTER TABLE IF EXISTS users ADD COLUMN IF NOT EXISTS job_title VARCHAR(80)`,

    `ALTER TABLE IF EXISTS users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ`,

    `ALTER TABLE IF EXISTS students ADD COLUMN IF NOT EXISTS photo_url TEXT`,

    `ALTER TABLE IF EXISTS students ADD COLUMN IF NOT EXISTS school_id UUID`,

    `ALTER TABLE IF EXISTS classes ADD COLUMN IF NOT EXISTS school_id UUID`,

    `ALTER TABLE IF EXISTS books ADD COLUMN IF NOT EXISTS school_id UUID`,

    `ALTER TABLE IF EXISTS books ADD COLUMN IF NOT EXISTS cover_url TEXT`,

    `ALTER TABLE IF EXISTS books ADD COLUMN IF NOT EXISTS cover_source TEXT`,

    `ALTER TABLE IF EXISTS books ADD COLUMN IF NOT EXISTS cover_checked_at TIMESTAMPTZ`,

    `CREATE INDEX IF NOT EXISTS users_school_id_idx ON users (school_id)`,

    `CREATE INDEX IF NOT EXISTS students_school_id_idx ON students (school_id)`,

    `CREATE INDEX IF NOT EXISTS classes_school_id_idx ON classes (school_id)`,

    `CREATE INDEX IF NOT EXISTS books_school_id_idx ON books (school_id)`,

    `CREATE INDEX IF NOT EXISTS books_cover_source_idx ON books (cover_source)`

  ];

 

  for (const statement of migrations) {

    await pool.query(statement);

  }

 

  const settings = await getSettings();

  const defaultSchool = await pool.query(`

    INSERT INTO schools (name, code, contact_email, phone, active)

    VALUES ($1, 'PRINCIPAL', $2, $3, TRUE)

    ON CONFLICT (code)

    DO UPDATE SET

      name = EXCLUDED.name,

      contact_email = COALESCE(EXCLUDED.contact_email, schools.contact_email),

      phone = COALESCE(EXCLUDED.phone, schools.phone),

      updated_at = NOW()

    RETURNING id

  `, [

    settings.school_name || "Escola Principal",

    settings.contact_email || null,

    settings.contact_phone || null

  ]);

 

  const schoolId = defaultSchool.rows[0].id;

 

  await pool.query(`UPDATE users SET school_id = $1 WHERE school_id IS NULL`, [schoolId]);

  await pool.query(`UPDATE students SET school_id = $1 WHERE school_id IS NULL`, [schoolId]);

  await pool.query(`UPDATE classes SET school_id = $1 WHERE school_id IS NULL`, [schoolId]);

  await pool.query(`UPDATE books SET school_id = $1 WHERE school_id IS NULL`, [schoolId]);

}

 

async function ensureInitialUsers() {

  const accounts = [

    {

      name: cleanText(process.env.ADMIN_NAME) || "Administrador BookShare",

      email: (cleanText(process.env.ADMIN_EMAIL) || "admin@bookshare.com").toLowerCase(),

      password: String(process.env.ADMIN_PASSWORD || "BookShare@2026"),

      role: "admin",

      variableGroup: "ADMIN"

    },

    {

      name: cleanText(process.env.LIBRARIAN1_NAME) || "Bibliotecária",

      email: (cleanText(process.env.LIBRARIAN1_EMAIL) || "biblioteca@bookshare.com").toLowerCase(),

      password: String(process.env.LIBRARIAN1_PASSWORD || "Biblioteca@2026"),

      role: "librarian",

      variableGroup: "LIBRARIAN1"

    }

  ];

 

  for (const account of accounts) {

    if (!account.email || account.password.length < 8) {

      console.warn(`${account.variableGroup}_EMAIL ou ${account.variableGroup}_PASSWORD não configurados corretamente. Essa conta inicial não foi criada.`);

      continue;

    }

 

    const existing = await pool.query(

      "SELECT id, role FROM users WHERE email = $1",

      [account.email]

    );

 

    if (existing.rows[0]) {

      if (existing.rows[0].role !== account.role) {

        await pool.query(

          `UPDATE users

           SET role = $1, active = TRUE, updated_at = NOW()

           WHERE id = $2`,

          [account.role, existing.rows[0].id]

        );

      }

      continue;

    }

 

    const passwordHash = await bcrypt.hash(account.password, 12);

    await pool.query(

      `INSERT INTO users (name, email, password_hash, role, active)

       VALUES ($1, $2, $3, $4, TRUE)`,

      [account.name, account.email, passwordHash, account.role]

    );

 

    console.log(`Conta inicial criada: ${account.email} (${account.role})`);

  }

}

 

 

function isDataImage(value) {

  return /^data:image\/(jpeg|jpg|png|webp);base64,/i.test(String(value || ""));

}

 

function editionForTitle(title) {

  const key = normalizeSearchText(title);

  return CATALOG_V30_EDITIONS.get(key) || OFFICIAL_EDITIONS.get(key) || null;

}

 

function dataImageParts(value) {

  const match = String(value || "").match(/^data:(image\/(?:jpeg|jpg|png|webp));base64,(.+)$/i);

  if (!match) return null;

  try {

    return { contentType: match[1].toLowerCase().replace("image/jpg", "image/jpeg"), buffer: Buffer.from(match[2], "base64") };

  } catch (_error) {

    return null;

  }

}

 

function jpegDimensions(buffer) {

  if (buffer.length < 24 || buffer[0] !== 0xff || buffer[1] !== 0xd8) return null;

  let offset = 2;

  while (offset + 9 < buffer.length) {

    if (buffer[offset] !== 0xff) { offset += 1; continue; }

    const marker = buffer[offset + 1];

    if ([0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf].includes(marker)) {

      return { height: buffer.readUInt16BE(offset + 5), width: buffer.readUInt16BE(offset + 7) };

    }

    if (marker === 0xd8 || marker === 0xd9) { offset += 2; continue; }

    const length = buffer.readUInt16BE(offset + 2);

    if (!length || length < 2) break;

    offset += 2 + length;

  }

  return null;

}

 

function pngDimensions(buffer) {

  if (buffer.length < 24 || buffer.toString("ascii",1,4) !== "PNG") return null;

  return { width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20) };

}

 

function imageDimensions(buffer, contentType) {

  if (contentType.includes("png")) return pngDimensions(buffer);

  if (contentType.includes("jpeg") || contentType.includes("jpg")) return jpegDimensions(buffer);

  return null;

}

 

 

function looksLikePlaceholderUrl(url) {

  const value = String(url || "").toLowerCase();

 

  return (

    value.includes("no_cover") ||

    value.includes("no-cover") ||

    value.includes("nocover") ||

    value.includes("image_not_available") ||

    value.includes("image-not-available") ||

    value.includes("googlebooks/images/no_cover") ||

    value.includes("book-placeholder")

  );

}

 

async function fetchRawCover(url) {

  if (!url) return null;

 

  const safeUrl = String(url)

    .replace(/^http:/i, "https:")

    .replace("&edge=curl", "");

 

  try {

    const response = await fetch(safeUrl, {

      redirect: "follow",

      headers: {

        "Accept": "image/avif,image/webp,image/apng,image/jpeg,image/png,image/gif,image/*,*/*;q=0.8",

        "User-Agent": "Mozilla/5.0 BookShare-Cover-Fetcher/9.1"

      },

      signal: AbortSignal.timeout(18000)

    });

 

    if (!response.ok) return null;

 

    const finalUrl = String(response.url || safeUrl);

    const contentType = String(

      response.headers.get("content-type") || ""

    ).split(";")[0].toLowerCase();

 

    if (looksLikePlaceholderUrl(finalUrl)) return null;

    if (!contentType.startsWith("image/")) return null;

 

    const buffer = Buffer.from(await response.arrayBuffer());

    if (!buffer.length) return null;

 

    return {

      buffer,

      contentType,

      sourceUrl: finalUrl

    };

  } catch (error) {

    console.warn(`Falha ao baixar capa: ${safeUrl}`, error.message);

    return null;

  }

}

 

async function coverFingerprint(buffer) {

  return sharp(buffer, { failOn: "none" })

    .rotate()

    .resize(32, 32, { fit: "fill" })

    .greyscale()

    .raw()

    .toBuffer();

}

 

function fingerprintDistance(first, second) {

  if (!first || !second || first.length !== second.length) return Infinity;

 

  let total = 0;

  for (let index = 0; index < first.length; index += 1) {

    total += Math.abs(first[index] - second[index]);

  }

 

  return total / first.length;

}

 

async function primeCoverPlaceholderHashes() {

  const placeholderUrls = [

    "https://books.google.com/googlebooks/images/no_cover_thumb.gif",

    "https://books.google.com/books/content?vid=ISBN0000000000000&printsec=frontcover&img=1&zoom=1&source=gbs_api",

    "https://books.google.com/books/content?vid=ISBN0000000000000&printsec=frontcover&img=1&zoom=2&source=gbs_api",

    "https://books.google.com/books/content?id=BOOKSHARE_INVALID_VOLUME&printsec=frontcover&img=1&zoom=2&source=gbs_api"

  ];

 

  for (const url of placeholderUrls) {

    const raw = await fetchRawCover(url);

    if (!raw?.buffer) continue;

 

    try {

      const fingerprint = await coverFingerprint(raw.buffer);

      coverPlaceholderHashes.add(fingerprint.toString("base64"));

    } catch (_error) {

      // Ignora placeholders que o Sharp não conseguir abrir.

    }

  }

 

  console.log(`Assinaturas visuais de placeholders: ${coverPlaceholderHashes.size}.`);

}

 

async function downloadVerifiedCover(url) {

  if (looksLikePlaceholderUrl(url)) return null;

 

  const result = await fetchRawCover(url);

  if (!result) return null;

 

  const { buffer, sourceUrl } = result;

  if (looksLikePlaceholderUrl(sourceUrl)) return null;

  if (buffer.length < 5000 || buffer.length > 8_000_000) return null;

 

  try {

    const image = sharp(buffer, { failOn: "none" }).rotate();

    const metadata = await image.metadata();

 

    if (!metadata.width || !metadata.height) return null;

    if (metadata.width < 100 || metadata.height < 140) return null;

    if (metadata.height <= metadata.width * 1.02) return null;

 

    const stats = await image.stats();

    const averageMean = stats.channels

      .slice(0, 3)

      .reduce((sum, channel) => sum + channel.mean, 0) / Math.min(3, stats.channels.length);

    const averageDeviation = stats.channels

      .slice(0, 3)

      .reduce((sum, channel) => sum + channel.stdev, 0) / Math.min(3, stats.channels.length);

 

    // Rejeita imagens praticamente vazias.

    if (averageMean > 242 && averageDeviation < 9) return null;

 

    const candidateFingerprint = await coverFingerprint(buffer);

 

    for (const encoded of coverPlaceholderHashes) {

      const placeholderFingerprint = Buffer.from(encoded, "base64");

      if (fingerprintDistance(candidateFingerprint, placeholderFingerprint) < 8.5) {

        return null;

      }

    }

 

    const normalizedBuffer = await image

      .resize({

        width: 520,

        height: 780,

        fit: "inside",

        withoutEnlargement: true,

        background: { r: 246, g: 243, b: 236, alpha: 1 }

      })

      .flatten({ background: "#f6f3ec" })

      .jpeg({ quality: 84, mozjpeg: true })

      .toBuffer();

 

    return {

      buffer: normalizedBuffer,

      contentType: "image/jpeg",

      sourceUrl

    };

  } catch (_error) {

    return null;

  }

}

 

function imageLinksFromVolume(volume) {

  const links = volume?.volumeInfo?.imageLinks || {};

  return [links.extraLarge,links.large,links.medium,links.small,links.thumbnail,links.smallThumbnail]

    .filter(Boolean)

    .map(url => String(url).replace(/^http:/i,"https:").replace("&edge=curl","").replace("zoom=1","zoom=3"));

}

 

async function googleVolume(volumeId) {

  if (!volumeId) return null;

  try {

    const params = new URLSearchParams();

    if (GOOGLE_BOOKS_API_KEY) params.set("key",GOOGLE_BOOKS_API_KEY);

    const suffix = params.toString() ? `?${params}` : "";

    const response = await fetch(`https://www.googleapis.com/books/v1/volumes/${encodeURIComponent(volumeId)}${suffix}`, {

      headers: { "Accept":"application/json", "User-Agent":"BookShare-Official-Covers/5.0" },

      signal: AbortSignal.timeout(15000)

    });

    if (!response.ok) return null;

    return await response.json();

  } catch (_error) { return null; }

}

 

async function googleVolumeByIsbn(isbn13) {

  if (!isbn13) return null;

  try {

    const params = new URLSearchParams({ q:`isbn:${isbn13}`, maxResults:"5", projection:"full", printType:"books" });

    if (GOOGLE_BOOKS_API_KEY) params.set("key",GOOGLE_BOOKS_API_KEY);

    const response = await fetch(`https://www.googleapis.com/books/v1/volumes?${params}`, {

      headers: { "Accept":"application/json", "User-Agent":"BookShare-Official-Covers/5.0" },

      signal: AbortSignal.timeout(15000)

    });

    if (!response.ok) return null;

    const data = await response.json();

    const normalized = String(isbn13).replace(/\D/g,"");

    const items = Array.isArray(data.items) ? data.items : [];

    return items.find(item => (item.volumeInfo?.industryIdentifiers || []).some(id => String(id.identifier).replace(/\D/g,"") === normalized)) || items[0] || null;

  } catch (_error) { return null; }

}

 

async function coverFromGoogleVolume(volume) {

  if (!volume?.id) return null;

 

  // Só usa URLs realmente fornecidas por imageLinks.

  // Não constrói URL de capa quando a edição não possui imagem,

  // porque isso retorna o placeholder "image not available".

  const urls = [...new Set(imageLinksFromVolume(volume))];

 

  for (const url of urls) {

    const image = await downloadVerifiedCover(url);

    if (image) {

      return {

        ...image,

        source: "Google Books — imagem original da edição"

      };

    }

  }

 

  return null;

}

 

async function coverFromOpenLibraryIsbn(isbn13) {

  if (!isbn13) return null;

  for (const size of ["L","M"]) {

    const image = await downloadVerifiedCover(`https://covers.openlibrary.org/b/isbn/${encodeURIComponent(isbn13)}-${size}.jpg?default=false`);

    if (image) return { ...image, source:"Open Library — ISBN exato" };

  }

  return null;

}

 

 

function scoreCoverResult(foundTitle, foundAuthors, wantedTitle, wantedAuthor) {

  const normalizedFoundTitle = normalizeSearchText(foundTitle || "");

  const normalizedFoundAuthors = normalizeSearchText(foundAuthors || "");

  const normalizedWantedTitle = normalizeSearchText(wantedTitle || "");

  const normalizedWantedAuthor = normalizeSearchText(wantedAuthor || "");

 

  let score = 0;

 

  if (normalizedFoundTitle === normalizedWantedTitle) score += 120;

  else if (normalizedFoundTitle.startsWith(normalizedWantedTitle)) score += 75;

  else if (normalizedFoundTitle.includes(normalizedWantedTitle)) score += 55;

  else if (normalizedWantedTitle.includes(normalizedFoundTitle)) score += 25;

 

  const authorWords = normalizedWantedAuthor

    .split(" ")

    .filter(word => word.length > 2);

 

  const matches = authorWords.filter(word => normalizedFoundAuthors.includes(word)).length;

  score += matches * 18;

 

  if (authorWords.length && matches === authorWords.length) score += 35;

 

  return score;

}

 

async function coverFromGoogleSearch(title, author) {

  const searches = [

    `intitle:"${title}"${author ? ` inauthor:"${author}"` : ""}`,

    `"${title}"${author ? ` ${author}` : ""}`,

    `${title}${author ? ` ${author}` : ""}`

  ];

 

  for (const searchText of searches) {

    try {

      const params = new URLSearchParams({

        q: searchText,

        maxResults: "30",

        projection: "full",

        printType: "books",

        orderBy: "relevance"

      });

 

      if (GOOGLE_BOOKS_API_KEY) params.set("key", GOOGLE_BOOKS_API_KEY);

 

      const response = await fetch(

        `https://www.googleapis.com/books/v1/volumes?${params.toString()}`,

        {

          headers: {

            "Accept": "application/json",

            "User-Agent": "BookShare-Original-Covers/6.0"

          },

          signal: AbortSignal.timeout(15000)

        }

      );

 

      if (!response.ok) continue;

 

      const data = await response.json();

 

      const ranked = (Array.isArray(data.items) ? data.items : [])

        .filter(item => item?.volumeInfo?.imageLinks)

        .map(item => ({

          item,

          score: scoreCoverResult(

            item.volumeInfo?.title,

            (item.volumeInfo?.authors || []).join(" "),

            title,

            author

          )

        }))

        .sort((a, b) => b.score - a.score)

        .slice(0, 10);

 

      for (const candidate of ranked) {

        if (candidate.score < 50) continue;

 

        const cover = await coverFromGoogleVolume(candidate.item);

        if (cover) {

          return {

            ...cover,

            source: "Google Books — edição original localizada por título e autor"

          };

        }

      }

    } catch (error) {

      console.warn(`Google Books search failed for ${title}:`, error.message);

    }

  }

 

  return null;

}

 

async function coverFromOpenLibrarySearch(title, author) {

  try {

    const params = new URLSearchParams({

      title,

      author: author || "",

      limit: "30",

      fields: "cover_i,title,author_name"

    });

 

    const response = await fetch(

      `https://openlibrary.org/search.json?${params.toString()}`,

      {

        headers: {

          "Accept": "application/json",

          "User-Agent": "BookShare-Original-Covers/6.0"

        },

        signal: AbortSignal.timeout(15000)

      }

    );

 

    if (!response.ok) return null;

 

    const data = await response.json();

 

    const ranked = (Array.isArray(data.docs) ? data.docs : [])

      .filter(item => item.cover_i)

      .map(item => ({

        item,

        score: scoreCoverResult(

          item.title,

          (item.author_name || []).join(" "),

          title,

          author

        )

      }))

      .sort((a, b) => b.score - a.score)

      .slice(0, 10);

 

    for (const candidate of ranked) {

      if (candidate.score < 45) continue;

 

      for (const size of ["L", "M"]) {

        const url =

          `https://covers.openlibrary.org/b/id/${candidate.item.cover_i}-${size}.jpg?default=false`;

 

        const image = await downloadVerifiedCover(url);

 

        if (image) {

          return {

            ...image,

            source: "Open Library — edição original localizada por título e autor"

          };

        }

      }

    }

  } catch (error) {

    console.warn(`Open Library search failed for ${title}:`, error.message);

  }

 

  return null;

}

 

async function resolveOfficialEditionCover(title, authorOverride = "") {

  const normalizedTitle = normalizeSearchText(title);

  const edition = editionForTitle(title);

  const cacheKey = `${normalizedTitle}::${normalizeSearchText(authorOverride)}`;

 

  if (bookCoverCache.has(cacheKey)) return bookCoverCache.get(cacheKey);

 

  const directCandidates =

    PERMANENT_COVER_CANDIDATES.get(normalizedTitle) || [];

 

  // 1. Links específicos da edição já definidos dentro do server.js.

  for (const url of directCandidates) {

    const image = await downloadVerifiedCover(url);

 

    if (image) {

      const result = {

        dataUri:

          `data:${image.contentType};base64,${image.buffer.toString("base64")}`,

        contentType: image.contentType,

        buffer: image.buffer,

        source: "Lista fixa verificada V28"

      };

 

      bookCoverCache.set(cacheKey, result);

      return result;

    }

  }

 

  if (!edition) return null;

 

  const author = edition.author || authorOverride || "";

  let cover = null;

 

  // 2. ISBN exato da edição.

  if (edition.isbn13) {

    const byIsbn = await googleVolumeByIsbn(edition.isbn13);

    cover = await coverFromGoogleVolume(byIsbn);

 

    if (!cover) {

      cover = await coverFromOpenLibraryIsbn(edition.isbn13);

    }

  }

 

  // 3. Volume exato previamente identificado.

  if (!cover && edition.googleVolumeId) {

    const exactVolume = await googleVolume(edition.googleVolumeId);

    cover = await coverFromGoogleVolume(exactVolume);

  }

 

  // 4. Busca exata por título e autor.

  if (!cover) {

    cover = await coverFromGoogleSearch(

      edition.title || title,

      author

    );

  }

 

  if (!cover) {

    cover = await coverFromOpenLibrarySearch(

      edition.title || title,

      author

    );

  }

 

  if (!cover) {

    cover = await coverFromGoogleSearch(

      edition.title || title,

      ""

    );

  }

 

  if (!cover) {

    cover = await coverFromOpenLibrarySearch(

      edition.title || title,

      ""

    );

  }

 

  if (!cover) return null;

 

  const result = {

    dataUri:

      `data:${cover.contentType};base64,${cover.buffer.toString("base64")}`,

    contentType: cover.contentType,

    buffer: cover.buffer,

    source: cover.source || "Edição original verificada V28"

  };

 

  bookCoverCache.set(cacheKey, result);

  return result;

}

 

function delay(milliseconds) { return new Promise(resolve => setTimeout(resolve,milliseconds)); }

 

async function syncBookCovers({ force = false } = {}) {

  if (bookCoverSyncState.running) return bookCoverSyncState;

  bookCoverSyncState.running=true;

  Object.assign(bookCoverSyncState,{total:0,processed:0,updated:0,failed:0,startedAt:new Date().toISOString(),finishedAt:null,currentTitle:null});

  try {

    const result = await pool.query(`SELECT id,title,author,cover_url,cover_source FROM books WHERE active=TRUE ORDER BY title`);

    const targets=result.rows.filter(book => {

      if (!editionForTitle(book.title)) return false;

      if (book.cover_source === "manual-upload") return false;

      return force || book.cover_source !== "verified-original-v30" || !isDataImage(book.cover_url);

    });

    bookCoverSyncState.total=targets.length;

    let cursor=0;

    const worker=async()=>{

      while (cursor<targets.length) {

        const book=targets[cursor++];

        bookCoverSyncState.currentTitle=book.title;

        try {

          const cover=await resolveOfficialEditionCover(book.title, book.author);

          if (cover) {

            await pool.query(`UPDATE books SET cover_url=$1,cover_source='verified-original-v30',cover_checked_at=NOW(),updated_at=NOW() WHERE id=$2`,[cover.dataUri,book.id]);

            bookCoverSyncState.updated+=1;

          } else {

            await pool.query(`UPDATE books SET cover_source='official-not-found',cover_checked_at=NOW(),updated_at=NOW() WHERE id=$1`,[book.id]);

            bookCoverSyncState.failed+=1;

          }

        } catch (error) {

          bookCoverSyncState.failed+=1;

          console.warn(`Official cover failed for ${book.title}:`,error.message);

        } finally { bookCoverSyncState.processed+=1; await delay(100); }

      }

    };

    await Promise.all([worker(),worker(),worker()]);

  } finally {

    bookCoverSyncState.running=false; bookCoverSyncState.currentTitle=null; bookCoverSyncState.finishedAt=new Date().toISOString();

    console.log("Official cover sync finished:",bookCoverSyncState);

  }

  return bookCoverSyncState;

}

 

app.get("/api/public/book-cover", asyncRoute(async (req, res) => {

  const title=requiredText(req.query.title,"o título",180);

  const bookResult=await pool.query(`SELECT id,title,author,cover_url,cover_source FROM books WHERE LOWER(title)=LOWER($1) LIMIT 1`,[title]);

  const book=bookResult.rows[0];

  let parts=dataImageParts(book?.cover_url);

  if (!parts && editionForTitle(book?.title || title)) {

    const cover=await resolveOfficialEditionCover(book?.title || title, book?.author || cleanText(req.query.author,160) || "");

    if (cover) {

      parts={contentType:cover.contentType,buffer:cover.buffer};

      if (book?.id) await pool.query(`UPDATE books SET cover_url=$1,cover_source='verified-original-v30',cover_checked_at=NOW(),updated_at=NOW() WHERE id=$2`,[cover.dataUri,book.id]);

    }

  }

  if (parts) {

    res.set("Content-Type",parts.contentType);

    res.set("Cache-Control","public,max-age=2592000,immutable");

    res.set("Access-Control-Allow-Origin","*");

    return res.send(parts.buffer);

  }

  res.set("Content-Type","image/svg+xml; charset=utf-8");

  res.set("Cache-Control","public,max-age=600");

  return res.send(`<svg xmlns="http://www.w3.org/2000/svg" width="420" height="640"><rect width="420" height="640" rx="28" fill="#f4f1e9"/><path d="M110 190c55-24 100-10 100-10v250s-45-12-100 12V190Zm200 0c-55-24-100-10-100-10v250s45-12 100 12V190Z" fill="#dcebe6" stroke="#176b63" stroke-width="9"/><path d="M210 180v250" stroke="#176b63" stroke-width="9"/><text x="210" y="520" text-anchor="middle" font-family="Arial" font-size="22" fill="#66736f">Capa original não localizada</text></svg>`);

}));

 

app.get("/api/public/book-covers/status", (_req, res) => {

  res.json(bookCoverSyncState);

});

 

app.post("/api/admin/book-covers/sync", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const force = cleanBoolean(req.body?.force, false);

  if (!bookCoverSyncState.running) {

    syncBookCovers({ force }).catch(error => console.error("Background cover sync error:", error));

  }

  res.status(202).json({ message: "Sincronização de capas iniciada.", status: bookCoverSyncState });

}));

 

app.get("/api/health", asyncRoute(async (_req, res) => {

  const result = await pool.query("SELECT NOW() AS database_time");

  res.json({

    status: "ok",

    database: "connected",

    database_time: result.rows[0].database_time,

    environment: NODE_ENV

  });

}));

 

app.post("/api/auth/login", asyncRoute(async (req, res) => {

  const email = cleanEmail(req.body.email);

  const password = String(req.body.password || "");

 

  if (!password) throw httpError(400, "Informe a senha.");

 

  const result = await pool.query(

    `SELECT

       u.id,

       u.name,

       u.email,

       u.password_hash,

       u.role,

       u.active,

       u.avatar_url,

       u.phone,

       u.job_title,

       u.school_id,

       s.name AS school_name

     FROM users u

     LEFT JOIN schools s ON s.id = u.school_id

     WHERE u.email = $1

       AND u.deleted_at IS NULL`,

    [email]

  );

 

  const user = result.rows[0];

  if (!user || !user.active) throw httpError(401, "E-mail ou senha incorretos.");

 

  const passwordMatches = await bcrypt.compare(password, user.password_hash);

  if (!passwordMatches) throw httpError(401, "E-mail ou senha incorretos.");

 

  await pool.query(

    `UPDATE users

     SET last_login_at = NOW(), updated_at = NOW()

     WHERE id = $1`,

    [user.id]

  );

 

  res.json({

    token: signToken(user),

    user: {

      id: user.id,

      name: user.name,

      email: user.email,

      role: user.role,

      avatar_url: user.avatar_url || null,

      phone: user.phone || null,

      job_title: user.job_title || null,

      school_id: user.school_id || null,

      school_name: user.school_name || null

    }

  });

}));

 

app.get("/api/auth/me", authenticate, asyncRoute(async (req, res) => {

  res.json({ user: req.user });

}));

 

app.put("/api/auth/profile", authenticate, asyncRoute(async (req, res) => {

  const name = requiredText(req.body.name, "o nome", 120);

  const avatarUrl = cleanText(req.body.avatar_url);

  const phone = cleanText(req.body.phone, 40);

 

  if (avatarUrl && (!avatarUrl.startsWith("data:image/") || avatarUrl.length > 2200000)) {

    throw httpError(400, "A foto enviada é inválida ou muito grande.");

  }

 

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

    const result = await client.query(`

      UPDATE users

      SET name = $1,

          avatar_url = $2,

          phone = $3,

          updated_at = NOW()

      WHERE id = $4

      RETURNING id, name, email, role, active, avatar_url, phone, job_title, school_id, last_login_at

    `, [name, avatarUrl, phone, req.user.id]);

    await audit(client, req, "update", "user", req.user.id, { self_profile: true, name });

    await client.query("COMMIT");

    res.json({ user: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.put("/api/auth/change-password", authenticate, asyncRoute(async (req, res) => {

  const currentPassword = String(req.body.current_password || "");

  const newPassword = String(req.body.new_password || "");

 

  if (newPassword.length < 8) throw httpError(400, "A nova senha deve ter pelo menos 8 caracteres.");

 

  const result = await pool.query(

    "SELECT password_hash FROM users WHERE id = $1",

    [req.user.id]

  );

 

  const matches = await bcrypt.compare(currentPassword, result.rows[0].password_hash);

  if (!matches) throw httpError(400, "A senha atual está incorreta.");

 

  const passwordHash = await bcrypt.hash(newPassword, 12);

  const client = await pool.connect();

 

  try {

    await client.query("BEGIN");

    await client.query(

      `UPDATE users

       SET password_hash = $1, updated_at = NOW()

       WHERE id = $2`,

      [passwordHash, req.user.id]

    );

    await audit(client, req, "password", "user", req.user.id, { self_change: true });

    await client.query("COMMIT");

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

 

  res.json({ message: "Senha alterada com sucesso." });

}));

 

 

app.get("/api/notifications", authenticate, requireRole("librarian"), asyncRoute(async (req, res) => {

  const settings = await getSettings();

  const dueSoonDays = Number(settings.due_soon_days || 2);

 

  const [loans, reservations] = await Promise.all([

    pool.query(`

      SELECT

        l.id,

        l.due_date,

        CURRENT_DATE - l.due_date AS overdue_days,

        s.full_name AS student_name,

        b.title AS book_title,

        c.name AS class_name

      FROM loans l

      JOIN students s ON s.id = l.student_id

      LEFT JOIN classes c ON c.id = s.class_id

      JOIN book_copies bc ON bc.id = l.copy_id

      JOIN books b ON b.id = bc.book_id

      WHERE l.status = 'active'

        AND l.due_date <= CURRENT_DATE + $1::INT

        AND ($2::UUID IS NULL OR s.school_id = $2::UUID)

      ORDER BY l.due_date ASC, s.full_name

      LIMIT 40

    `, [dueSoonDays, req.user.school_id || null]),

    pool.query(`

      SELECT

        r.id,

        r.expires_at,

        s.full_name AS student_name,

        b.title AS book_title

      FROM reservations r

      JOIN students s ON s.id = r.student_id

      JOIN books b ON b.id = r.book_id

      WHERE r.status = 'ready'

        AND ($1::UUID IS NULL OR s.school_id = $1::UUID)

      ORDER BY r.expires_at NULLS LAST, r.created_at

      LIMIT 20

    `, [req.user.school_id || null])

  ]);

 

  const items = [];

 

  for (const item of loans.rows) {

    const overdueDays = Number(item.overdue_days || 0);

 

    if (overdueDays > 0) {

      items.push({

        key: `overdue:${item.id}:${item.due_date}`,

        type: overdueDays >= 7 ? "danger" : "warning",

        icon: "!",

        title: `${item.student_name} está com devolução atrasada`,

        message: `${item.book_title}${item.class_name ? ` · ${item.class_name}` : ""}`,

        time: `${overdueDays} dia(s) de atraso`,

        route: "pendencias"

      });

    } else if (overdueDays === 0) {

      items.push({

        key: `today:${item.id}:${item.due_date}`,

        type: "warning",

        icon: "◷",

        title: "Devolução vence hoje",

        message: `${item.student_name} · ${item.book_title}`,

        time: "Prazo final de devolução",

        route: "emprestimos"

      });

    } else {

      items.push({

        key: `soon:${item.id}:${item.due_date}`,

        type: "default",

        icon: "⇄",

        title: "Devolução próxima",

        message: `${item.student_name} · ${item.book_title}`,

        time: `Vence em ${Math.abs(overdueDays)} dia(s)`,

        route: "emprestimos"

      });

    }

  }

 

  for (const item of reservations.rows) {

    items.push({

      key: `reservation:${item.id}:${item.expires_at || ""}`,

      type: "default",

      icon: "◇",

      title: "Reserva pronta para retirada",

      message: `${item.student_name} · ${item.book_title}`,

      time: item.expires_at ? `Retirar até ${item.expires_at}` : "Aguardando retirada",

      route: "reservas"

    });

  }

 

  res.json({

    generated_at: new Date().toISOString(),

    notifications: items

  });

}));

 

app.get("/api/dashboard", authenticate, asyncRoute(async (_req, res) => {

  const settings = await getSettings();

 

  const [

    bookSummary,

    loanSummary,

    studentSummary,

    reservationSummary,

    recentLoans,

    dueToday,

    popularBooks,

    circulation

  ] = await Promise.all([

    pool.query(`

      SELECT

        COUNT(DISTINCT b.id)::INT AS total_titles,

        COUNT(bc.id)::INT AS total_copies,

        COUNT(bc.id) FILTER (WHERE bc.status = 'available')::INT AS available_copies,

        COUNT(bc.id) FILTER (WHERE bc.status = 'loaned')::INT AS loaned_copies,

        COUNT(bc.id) FILTER (WHERE bc.status IN ('damaged', 'lost', 'maintenance'))::INT AS attention_copies

      FROM books b

      LEFT JOIN book_copies bc ON bc.book_id = b.id

      WHERE b.active = TRUE

    `),

    pool.query(`

      SELECT

        COUNT(*) FILTER (WHERE status = 'active')::INT AS active,

        COUNT(*) FILTER (WHERE status = 'active' AND due_date < CURRENT_DATE)::INT AS overdue,

        COUNT(*) FILTER (WHERE status = 'active' AND due_date = CURRENT_DATE)::INT AS due_today,

        COUNT(*) FILTER (

          WHERE status = 'active'

            AND due_date BETWEEN CURRENT_DATE AND CURRENT_DATE + $1::INT

        )::INT AS due_soon,

        COALESCE(MAX(

          CASE WHEN status = 'active' AND due_date < CURRENT_DATE

          THEN CURRENT_DATE - due_date ELSE 0 END

        ), 0)::INT AS max_overdue_days

      FROM loans

    `, [settings.due_soon_days]),

    pool.query(`

      SELECT

        COUNT(*) FILTER (WHERE active = TRUE)::INT AS active,

        (SELECT COUNT(*)::INT FROM classes WHERE active = TRUE) AS classes

      FROM students

    `),

    pool.query(`

      SELECT

        COUNT(*) FILTER (WHERE status = 'active')::INT AS active,

        COUNT(*) FILTER (WHERE status = 'ready')::INT AS ready

      FROM reservations

    `),

    pool.query(`

      SELECT

        l.id,

        l.student_id,

        l.loan_date,

        l.due_date,

        l.status,

        l.renewal_count,

        s.full_name AS student_name,

        s.registration_number,

        c.name AS class_name,

        b.title AS book_title,

        b.author AS book_author,

        b.cover_url,

        bc.inventory_code

      FROM loans l

      JOIN students s ON s.id = l.student_id

      LEFT JOIN classes c ON c.id = s.class_id

      JOIN book_copies bc ON bc.id = l.copy_id

      JOIN books b ON b.id = bc.book_id

      ORDER BY l.created_at DESC

      LIMIT 10

    `),

    pool.query(`

      SELECT

        l.id,

        l.student_id,

        l.loan_date,

        l.due_date,

        l.status,

        s.full_name AS student_name,

        s.registration_number,

        c.name AS class_name,

        b.title AS book_title,

        b.author AS book_author,

        b.cover_url,

        bc.inventory_code

      FROM loans l

      JOIN students s ON s.id = l.student_id

      LEFT JOIN classes c ON c.id = s.class_id

      JOIN book_copies bc ON bc.id = l.copy_id

      JOIN books b ON b.id = bc.book_id

      WHERE l.status = 'active' AND l.due_date = CURRENT_DATE

      ORDER BY s.full_name

      LIMIT 10

    `),

    pool.query(`

      SELECT

        b.id,

        b.title,

        b.author,

        b.cover_url,

        COUNT(l.id)::INT AS loan_count

      FROM books b

      JOIN book_copies bc ON bc.book_id = b.id

      JOIN loans l ON l.copy_id = bc.id

      GROUP BY b.id

      ORDER BY loan_count DESC, b.title

      LIMIT 8

    `),

    pool.query(`

      WITH days AS (

        SELECT generate_series(CURRENT_DATE - INTERVAL '29 days', CURRENT_DATE, INTERVAL '1 day')::DATE AS day

      ),

      loan_counts AS (

        SELECT loan_date AS day, COUNT(*)::INT AS count

        FROM loans

        WHERE loan_date >= CURRENT_DATE - INTERVAL '29 days'

        GROUP BY loan_date

      ),

      return_counts AS (

        SELECT returned_at::DATE AS day, COUNT(*)::INT AS count

        FROM loans

        WHERE returned_at::DATE >= CURRENT_DATE - INTERVAL '29 days'

        GROUP BY returned_at::DATE

      )

      SELECT

        d.day,

        COALESCE(lc.count, 0)::INT AS loans,

        COALESCE(rc.count, 0)::INT AS returns

      FROM days d

      LEFT JOIN loan_counts lc ON lc.day = d.day

      LEFT JOIN return_counts rc ON rc.day = d.day

      ORDER BY d.day

    `)

  ]);

 

  const [staffSummary, schoolSummary] = await Promise.all([

    pool.query(`

      SELECT COUNT(*)::INT AS active_staff

      FROM users

      WHERE active = TRUE

        AND deleted_at IS NULL

        AND role = 'librarian'

    `),

    pool.query(`

      SELECT COUNT(*)::INT AS active_schools

      FROM schools

      WHERE active = TRUE

    `)

  ]);

 

  res.json({

    admin: {

      active_staff: staffSummary.rows[0].active_staff,

      active_students: studentSummary.rows[0].active,

      active_schools: schoolSummary.rows[0].active_schools,

      active_books: bookSummary.rows[0].total_titles

    },

    books: bookSummary.rows[0],

    loans: loanSummary.rows[0],

    students: studentSummary.rows[0],

    reservations: reservationSummary.rows[0],

    recent_loans: recentLoans.rows,

    due_today: dueToday.rows,

    popular_books: popularBooks.rows,

    circulation: circulation.rows

  });

}));

 

 

app.get("/api/schools", authenticate, requireRole("admin"), asyncRoute(async (_req, res) => {

  const result = await pool.query(`

    SELECT

      s.*,

      COUNT(DISTINCT u.id) FILTER (WHERE u.deleted_at IS NULL AND u.active = TRUE)::INT AS staff_count,

      COUNT(DISTINCT st.id) FILTER (WHERE st.active = TRUE)::INT AS student_count

    FROM schools s

    LEFT JOIN users u ON u.school_id = s.id

    LEFT JOIN students st ON st.school_id = s.id

    GROUP BY s.id

    ORDER BY s.active DESC, s.name

  `);

 

  res.json({ schools: result.rows });

}));

 

app.post("/api/schools", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const name = requiredText(req.body.name, "o nome da escola", 140);

  const code = requiredText(req.body.code, "o código da escola", 30).toUpperCase();

  const address = cleanText(req.body.address, 220);

  const contactEmail = cleanText(req.body.contact_email, 180);

  const phone = cleanText(req.body.phone, 40);

 

  const client = await pool.connect();

 

  try {

    await client.query("BEGIN");

 

    const result = await client.query(`

      INSERT INTO schools (name, code, address, contact_email, phone, active)

      VALUES ($1, $2, $3, $4, $5, TRUE)

      RETURNING *

    `, [name, code, address, contactEmail, phone]);

 

    await audit(client, req, "create", "school", result.rows[0].id, result.rows[0]);

    await client.query("COMMIT");

 

    res.status(201).json({ school: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    if (error.code === "23505") throw httpError(409, "Já existe uma escola com esse código.");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.put("/api/schools/:id", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const name = requiredText(req.body.name, "o nome da escola", 140);

  const code = requiredText(req.body.code, "o código da escola", 30).toUpperCase();

  const address = cleanText(req.body.address, 220);

  const contactEmail = cleanText(req.body.contact_email, 180);

  const phone = cleanText(req.body.phone, 40);

 

  const result = await pool.query(`

    UPDATE schools

    SET name = $1,

        code = $2,

        address = $3,

        contact_email = $4,

        phone = $5,

        updated_at = NOW()

    WHERE id = $6

    RETURNING *

  `, [name, code, address, contactEmail, phone, req.params.id]);

 

  if (!result.rows[0]) throw httpError(404, "Escola não encontrada.");

  res.json({ school: result.rows[0] });

}));

 

app.put("/api/schools/:id/status", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const active = cleanBoolean(req.body.active);

 

  const result = await pool.query(`

    UPDATE schools

    SET active = $1,

        updated_at = NOW()

    WHERE id = $2

    RETURNING *

  `, [active, req.params.id]);

 

  if (!result.rows[0]) throw httpError(404, "Escola não encontrada.");

  res.json({ school: result.rows[0] });

}));

 

app.get("/api/classes", authenticate, asyncRoute(async (_req, res) => {

  const result = await pool.query(`

    SELECT

      c.id,

      c.name,

      c.shift,

      c.school_year,

      c.teacher_name,

      c.active,

      c.created_at,

      c.updated_at,

      COUNT(DISTINCT s.id) FILTER (WHERE s.active = TRUE)::INT AS student_count,

      COUNT(DISTINCT l.id) FILTER (WHERE l.status = 'active')::INT AS active_loan_count,

      COUNT(DISTINCT l.id) FILTER (WHERE l.status = 'active' AND l.due_date < CURRENT_DATE)::INT AS overdue_count

    FROM classes c

    LEFT JOIN students s ON s.class_id = c.id

    LEFT JOIN loans l ON l.student_id = s.id

    GROUP BY c.id

    ORDER BY c.school_year DESC, c.name

  `);

  res.json({ classes: result.rows });

}));

 

app.post("/api/classes", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const name = requiredText(req.body.name, "o nome da turma", 60);

  const shift = requiredText(req.body.shift, "o turno", 30);

  const schoolYear = cleanInteger(req.body.school_year, { min: 2020, max: 2100, nullable: false });

  const teacherName = cleanText(req.body.teacher_name, 120);

 

  if (!["Manhã", "Tarde", "Noite", "Integral"].includes(shift)) throw httpError(400, "Turno inválido.");

 

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

    const result = await client.query(

      `INSERT INTO classes (name, shift, school_year, teacher_name, school_id)

       VALUES ($1, $2, $3, $4, $5)

       RETURNING *`,

      [name, shift, schoolYear, teacherName, req.user.school_id || null]

    );

    await audit(client, req, "create", "class", result.rows[0].id, result.rows[0]);

    await client.query("COMMIT");

    res.status(201).json({ class: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    if (error.code === "23505") throw httpError(409, "Essa turma já existe no mesmo ano e turno.");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.put("/api/classes/:id", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const name = requiredText(req.body.name, "o nome da turma", 60);

  const shift = requiredText(req.body.shift, "o turno", 30);

  const schoolYear = cleanInteger(req.body.school_year, { min: 2020, max: 2100, nullable: false });

  const teacherName = cleanText(req.body.teacher_name, 120);

 

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

    const result = await client.query(

      `UPDATE classes

       SET name = $1,

           shift = $2,

           school_year = $3,

           teacher_name = $4,

           updated_at = NOW()

       WHERE id = $5

       RETURNING *`,

      [name, shift, schoolYear, teacherName, req.params.id]

    );

 

    if (!result.rows[0]) throw httpError(404, "Turma não encontrada.");

    await audit(client, req, "update", "class", req.params.id, result.rows[0]);

    await client.query("COMMIT");

    res.json({ class: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    if (error.code === "23505") throw httpError(409, "Essa turma já existe no mesmo ano e turno.");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.put("/api/classes/:id/status", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const active = cleanBoolean(req.body.active);

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

    const result = await client.query(

      `UPDATE classes SET active = $1, updated_at = NOW()

       WHERE id = $2

       RETURNING *`,

      [active, req.params.id]

    );

    if (!result.rows[0]) throw httpError(404, "Turma não encontrada.");

    await audit(client, req, active ? "reactivate" : "archive", "class", req.params.id, { active });

    await client.query("COMMIT");

    res.json({ class: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.get("/api/students", authenticate, asyncRoute(async (_req, res) => {

  const result = await pool.query(`

    SELECT

      s.id,

      s.full_name,

      s.registration_number,

      s.class_id,

      s.roll_number,

      s.guardian_contact,

      s.photo_url,

      s.notes,

      s.active,

      s.created_at,

      s.updated_at,

      c.name AS class_name,

      c.shift,

      c.school_year,

      COUNT(l.id) FILTER (WHERE l.status = 'active')::INT AS active_loans,

      COUNT(l.id) FILTER (WHERE l.status = 'active' AND l.due_date < CURRENT_DATE)::INT AS overdue_loans,

      COUNT(l.id)::INT AS total_loans

    FROM students s

    LEFT JOIN classes c ON c.id = s.class_id

    LEFT JOIN loans l ON l.student_id = s.id

    GROUP BY s.id, c.id

    ORDER BY s.active DESC, s.full_name

  `);

  res.json({ students: result.rows });

}));

 

app.get("/api/students/:id", authenticate, asyncRoute(async (req, res) => {

  const studentResult = await pool.query(`

    SELECT

      s.*,

      c.name AS class_name,

      c.shift,

      c.school_year

    FROM students s

    LEFT JOIN classes c ON c.id = s.class_id

    WHERE s.id = $1

  `, [req.params.id]);

 

  const student = studentResult.rows[0];

  if (!student) throw httpError(404, "Aluno não encontrado.");

 

  const [activeLoans, history, notices] = await Promise.all([

    pool.query(`

      SELECT

        l.*,

        b.title AS book_title,

        b.author AS book_author,

        b.cover_url,

        bc.inventory_code

      FROM loans l

      JOIN book_copies bc ON bc.id = l.copy_id

      JOIN books b ON b.id = bc.book_id

      WHERE l.student_id = $1 AND l.status = 'active'

      ORDER BY l.due_date

    `, [req.params.id]),

    pool.query(`

      SELECT

        l.*,

        b.title AS book_title,

        b.author AS book_author,

        b.cover_url,

        bc.inventory_code

      FROM loans l

      JOIN book_copies bc ON bc.id = l.copy_id

      JOIN books b ON b.id = bc.book_id

      WHERE l.student_id = $1

      ORDER BY l.created_at DESC

      LIMIT 100

    `, [req.params.id]),

    pool.query(`

      SELECT

        n.*,

        u.name AS created_by_name,

        b.title AS book_title

      FROM notices n

      JOIN users u ON u.id = n.created_by

      JOIN loans l ON l.id = n.loan_id

      JOIN book_copies bc ON bc.id = l.copy_id

      JOIN books b ON b.id = bc.book_id

      WHERE l.student_id = $1

      ORDER BY n.created_at DESC

      LIMIT 100

    `, [req.params.id])

  ]);

 

  res.json({

    student,

    active_loans: activeLoans.rows,

    history: history.rows,

    notices: notices.rows

  });

}));

 

app.post("/api/students", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const fullName = requiredText(req.body.full_name, "o nome do aluno", 160);

  const registrationNumber = requiredText(req.body.registration_number, "a matrícula", 40);

  const classId = requiredText(req.body.class_id, "a turma");

  const rollNumber = cleanInteger(req.body.roll_number, { min: 1, max: 99 });

  const guardianContact = cleanText(req.body.guardian_contact, 80);

  const photoUrl = cleanText(req.body.photo_url);

  const notes = cleanText(req.body.notes);

 

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

 

    const classResult = await client.query("SELECT id, school_id FROM classes WHERE id = $1 AND active = TRUE", [classId]);

    if (!classResult.rows[0]) throw httpError(400, "Selecione uma turma ativa.");

 

    const result = await client.query(

      `INSERT INTO students

        (full_name, registration_number, class_id, roll_number, guardian_contact, photo_url, notes, school_id)

       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)

       RETURNING *`,

      [fullName, registrationNumber, classId, rollNumber, guardianContact, photoUrl, notes, classResult.rows[0].school_id || req.user.school_id || null]

    );

 

    await audit(client, req, "create", "student", result.rows[0].id, result.rows[0]);

    await client.query("COMMIT");

    res.status(201).json({ student: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    if (error.code === "23505") throw httpError(409, "Já existe um aluno com essa matrícula.");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.put("/api/students/:id", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const fullName = requiredText(req.body.full_name, "o nome do aluno", 160);

  const registrationNumber = requiredText(req.body.registration_number, "a matrícula", 40);

  const classId = requiredText(req.body.class_id, "a turma");

  const rollNumber = cleanInteger(req.body.roll_number, { min: 1, max: 99 });

  const guardianContact = cleanText(req.body.guardian_contact, 80);

  const photoUrl = cleanText(req.body.photo_url);

  const notes = cleanText(req.body.notes);

 

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

    const result = await client.query(

      `UPDATE students

       SET full_name = $1,

           registration_number = $2,

           class_id = $3,

           roll_number = $4,

           guardian_contact = $5,

           photo_url = $6,

           notes = $7,

           updated_at = NOW()

       WHERE id = $8

       RETURNING *`,

      [fullName, registrationNumber, classId, rollNumber, guardianContact, photoUrl, notes, req.params.id]

    );

    if (!result.rows[0]) throw httpError(404, "Aluno não encontrado.");

    await audit(client, req, "update", "student", req.params.id, result.rows[0]);

    await client.query("COMMIT");

    res.json({ student: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    if (error.code === "23505") throw httpError(409, "Já existe um aluno com essa matrícula.");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.delete("/api/students/:id", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const activeLoan = await pool.query(

    "SELECT 1 FROM loans WHERE student_id = $1 AND status = 'active' LIMIT 1",

    [req.params.id]

  );

  if (activeLoan.rows[0]) throw httpError(409, "O aluno possui empréstimos ativos e não pode ser arquivado.");

 

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

    const result = await client.query(

      `UPDATE students SET active = FALSE, updated_at = NOW()

       WHERE id = $1

       RETURNING *`,

      [req.params.id]

    );

    if (!result.rows[0]) throw httpError(404, "Aluno não encontrado.");

    await audit(client, req, "archive", "student", req.params.id, { full_name: result.rows[0].full_name });

    await client.query("COMMIT");

    res.json({ student: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.put("/api/students/:id/status", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const active = cleanBoolean(req.body.active);

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

    const result = await client.query(

      `UPDATE students SET active = $1, updated_at = NOW()

       WHERE id = $2

       RETURNING *`,

      [active, req.params.id]

    );

    if (!result.rows[0]) throw httpError(404, "Aluno não encontrado.");

    await audit(client, req, active ? "reactivate" : "archive", "student", req.params.id, { active });

    await client.query("COMMIT");

    res.json({ student: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.get("/api/categories", authenticate, asyncRoute(async (_req, res) => {

  const result = await pool.query(`

    SELECT

      c.id,

      c.name,

      c.active,

      COUNT(b.id) FILTER (WHERE b.active = TRUE)::INT AS book_count

    FROM categories c

    LEFT JOIN books b ON b.category_id = c.id

    WHERE c.active = TRUE

    GROUP BY c.id

    ORDER BY c.name

  `);

  res.json({ categories: result.rows });

}));

 

app.post("/api/categories", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const name = requiredText(req.body.name, "o nome da categoria", 90);

  const result = await pool.query(

    `INSERT INTO categories (name)

     VALUES ($1)

     ON CONFLICT (name) DO UPDATE SET active = TRUE

     RETURNING *`,

    [name]

  );

  res.status(201).json({ category: result.rows[0] });

}));

 

app.get("/api/books", authenticate, asyncRoute(async (_req, res) => {

  const result = await pool.query(`

    SELECT

      b.id,

      b.title,

      b.author,

      b.isbn,

      b.publisher,

      b.publication_year,

      b.category_id,

      b.shelf,

      b.description,

      CASE

        WHEN b.cover_source = 'manual-upload' THEN b.cover_url

        ELSE NULL

      END AS cover_url,

      b.cover_source,

      b.cover_checked_at,

      b.active,

      b.created_at,

      b.updated_at,

      c.name AS category_name,

      COUNT(bc.id)::INT AS total_copies,

      COUNT(bc.id) FILTER (WHERE bc.status = 'available')::INT AS available_copies,

      COUNT(bc.id) FILTER (WHERE bc.status = 'loaned')::INT AS loaned_copies,

      COUNT(bc.id) FILTER (WHERE bc.status = 'damaged')::INT AS damaged_copies,

      COUNT(bc.id) FILTER (WHERE bc.status = 'lost')::INT AS lost_copies,

      COUNT(bc.id) FILTER (WHERE bc.status = 'maintenance')::INT AS maintenance_copies,

      COUNT(l.id)::INT AS total_loan_count

    FROM books b

    LEFT JOIN categories c ON c.id = b.category_id

    LEFT JOIN book_copies bc ON bc.book_id = b.id

    LEFT JOIN loans l ON l.copy_id = bc.id

    WHERE b.active = TRUE

    GROUP BY b.id, c.id

    ORDER BY b.title

  `);

  res.json({ books: result.rows });

}));

 

app.get("/api/books/:id", authenticate, asyncRoute(async (req, res) => {

  const bookResult = await pool.query(`

    SELECT

      b.*,

      c.name AS category_name,

      COUNT(DISTINCT bc.id)::INT AS total_copies,

      COUNT(DISTINCT bc.id) FILTER (WHERE bc.status = 'available')::INT AS available_copies,

      COUNT(DISTINCT bc.id) FILTER (WHERE bc.status = 'loaned')::INT AS loaned_copies,

      COUNT(DISTINCT l.id)::INT AS total_loan_count

    FROM books b

    LEFT JOIN categories c ON c.id = b.category_id

    LEFT JOIN book_copies bc ON bc.book_id = b.id

    LEFT JOIN loans l ON l.copy_id = bc.id

    WHERE b.id = $1

    GROUP BY b.id, c.id

  `, [req.params.id]);

 

  const book = bookResult.rows[0];

  if (!book) throw httpError(404, "Livro não encontrado.");

 

  const [copies, recentLoans] = await Promise.all([

    pool.query(`

      SELECT * FROM book_copies

      WHERE book_id = $1

      ORDER BY created_at

    `, [req.params.id]),

    pool.query(`

      SELECT

        l.*,

        s.full_name AS student_name,

        c.name AS class_name,

        bc.inventory_code

      FROM loans l

      JOIN students s ON s.id = l.student_id

      LEFT JOIN classes c ON c.id = s.class_id

      JOIN book_copies bc ON bc.id = l.copy_id

      WHERE bc.book_id = $1

      ORDER BY l.created_at DESC

      LIMIT 30

    `, [req.params.id])

  ]);

 

  res.json({ book, copies: copies.rows, recent_loans: recentLoans.rows });

}));

 

app.post("/api/books", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const title = requiredText(req.body.title, "o título", 180);

  const author = requiredText(req.body.author, "o autor", 160);

  const quantity = cleanInteger(req.body.quantity, { min: 1, max: 999, nullable: false });

  const isbn = cleanText(req.body.isbn, 30);

  const publisher = cleanText(req.body.publisher, 120);

  const publicationYear = cleanInteger(req.body.publication_year, { min: 1000, max: 2100 });

  const categoryId = cleanText(req.body.category_id);

  const shelf = cleanText(req.body.shelf, 80);

  const description = cleanText(req.body.description);

  const coverUrl = cleanText(req.body.cover_url);

 

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

    const result = await client.query(

      `INSERT INTO books

        (title, author, isbn, publisher, publication_year, category_id, shelf, description, cover_url, cover_source, school_id)

       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)

       RETURNING *`,

      [title, author, isbn, publisher, publicationYear, categoryId, shelf, description, coverUrl, coverUrl ? "manual-upload" : null, req.user.school_id || null]

    );

 

    const book = result.rows[0];

    await createInventoryCodes(client, book.id, quantity, new Date().toISOString().slice(0, 10), "Cadastro inicial");

    await audit(client, req, "create", "book", book.id, { ...book, quantity });

    await client.query("COMMIT");

    res.status(201).json({ book });

  } catch (error) {

    await client.query("ROLLBACK");

    if (error.code === "23505") throw httpError(409, "Já existe um livro com esse ISBN.");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.put("/api/books/:id", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const title = requiredText(req.body.title, "o título", 180);

  const author = requiredText(req.body.author, "o autor", 160);

  const requestedQuantity = cleanInteger(req.body.quantity, { min: 1, max: 999, nullable: false });

  const isbn = cleanText(req.body.isbn, 30);

  const publisher = cleanText(req.body.publisher, 120);

  const publicationYear = cleanInteger(req.body.publication_year, { min: 1000, max: 2100 });

  const categoryId = cleanText(req.body.category_id);

  const shelf = cleanText(req.body.shelf, 80);

  const description = cleanText(req.body.description);

  const coverUrl = cleanText(req.body.cover_url);

 

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

 

    const copySummaryResult = await client.query(`

      SELECT

        COUNT(*)::INT AS total,

        COUNT(*) FILTER (WHERE status = 'available')::INT AS available

      FROM book_copies

      WHERE book_id = $1

    `, [req.params.id]);

 

    const copySummary = copySummaryResult.rows[0];

    const difference = requestedQuantity - copySummary.total;

 

    if (difference < 0 && Math.abs(difference) > copySummary.available) {

      throw httpError(409, "Não é possível reduzir essa quantidade porque existem exemplares indisponíveis.");

    }

 

    const result = await client.query(

      `UPDATE books

       SET title = $1,

           author = $2,

           isbn = $3,

           publisher = $4,

           publication_year = $5,

           category_id = $6,

           shelf = $7,

           description = $8,

           cover_url = $9,

           cover_source = $10,

           cover_checked_at = CASE WHEN $9 IS NULL THEN cover_checked_at ELSE NOW() END,

           updated_at = NOW()

       WHERE id = $11

       RETURNING *`,

      [title, author, isbn, publisher, publicationYear, categoryId, shelf, description, coverUrl, coverUrl ? "manual-upload" : null, req.params.id]

    );

 

    if (!result.rows[0]) throw httpError(404, "Livro não encontrado.");

 

    if (difference > 0) {

      await createInventoryCodes(client, req.params.id, difference, new Date().toISOString().slice(0, 10), "Acréscimo pelo cadastro do livro");

    }

 

    if (difference < 0) {

      await client.query(`

        DELETE FROM book_copies

        WHERE id IN (

          SELECT id FROM book_copies

          WHERE book_id = $1 AND status = 'available'

          ORDER BY created_at DESC

          LIMIT $2

        )

      `, [req.params.id, Math.abs(difference)]);

    }

 

    await audit(client, req, "update", "book", req.params.id, { ...result.rows[0], quantity: requestedQuantity });

    await client.query("COMMIT");

    res.json({ book: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    if (error.code === "23505") throw httpError(409, "Já existe outro livro com esse ISBN.");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.delete("/api/books/:id", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const activeLoan = await pool.query(`

    SELECT 1

    FROM loans l

    JOIN book_copies bc ON bc.id = l.copy_id

    WHERE bc.book_id = $1 AND l.status = 'active'

    LIMIT 1

  `, [req.params.id]);

 

  if (activeLoan.rows[0]) throw httpError(409, "O livro possui empréstimos ativos.");

 

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

    const result = await client.query(

      `UPDATE books SET active = FALSE, updated_at = NOW()

       WHERE id = $1

       RETURNING *`,

      [req.params.id]

    );

    if (!result.rows[0]) throw httpError(404, "Livro não encontrado.");

    await audit(client, req, "archive", "book", req.params.id, { title: result.rows[0].title });

    await client.query("COMMIT");

    res.json({ book: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.get("/api/copies", authenticate, asyncRoute(async (_req, res) => {

  const result = await pool.query(`

    SELECT

      bc.*,

      b.title AS book_title,

      b.author AS book_author,

      b.cover_url,

      b.shelf,

      l.id AS active_loan_id,

      s.full_name AS student_name,

      l.due_date

    FROM book_copies bc

    JOIN books b ON b.id = bc.book_id

    LEFT JOIN loans l ON l.copy_id = bc.id AND l.status = 'active'

    LEFT JOIN students s ON s.id = l.student_id

    WHERE b.active = TRUE

    ORDER BY b.title, bc.inventory_code

  `);

  res.json({ copies: result.rows });

}));

 

app.post("/api/copies", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const bookId = requiredText(req.body.book_id, "o livro");

  const quantity = cleanInteger(req.body.quantity, { min: 1, max: 100, nullable: false });

  const acquiredAt = cleanDate(req.body.acquired_at, "a data de aquisição");

  const notes = cleanText(req.body.condition_notes);

 

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

 

    const bookResult = await client.query("SELECT id, title FROM books WHERE id = $1 AND active = TRUE", [bookId]);

    if (!bookResult.rows[0]) throw httpError(404, "Livro não encontrado.");

 

    const copies = await createInventoryCodes(client, bookId, quantity, acquiredAt, notes);

    await audit(client, req, "create", "copy", bookId, { book_title: bookResult.rows[0].title, quantity });

    await client.query("COMMIT");

    res.status(201).json({ copies });

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.put("/api/copies/:id/status", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const status = requiredText(req.body.status, "a situação do exemplar");

  const notes = cleanText(req.body.condition_notes);

  const allowed = ["available", "maintenance", "damaged", "lost"];

  if (!allowed.includes(status)) throw httpError(400, "Situação do exemplar inválida.");

 

  const activeLoan = await pool.query(

    "SELECT 1 FROM loans WHERE copy_id = $1 AND status = 'active' LIMIT 1",

    [req.params.id]

  );

  if (activeLoan.rows[0]) throw httpError(409, "O exemplar está emprestado e não pode ter a situação alterada manualmente.");

 

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

    const result = await client.query(

      `UPDATE book_copies

       SET status = $1, condition_notes = $2, updated_at = NOW()

       WHERE id = $3

       RETURNING *`,

      [status, notes, req.params.id]

    );

    if (!result.rows[0]) throw httpError(404, "Exemplar não encontrado.");

    await audit(client, req, "status", "copy", req.params.id, { status, condition_notes: notes });

    await client.query("COMMIT");

    res.json({ copy: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.get("/api/loans", authenticate, asyncRoute(async (_req, res) => {

  const result = await pool.query(`

    SELECT

      l.id,

      l.student_id,

      l.copy_id,

      l.created_by,

      l.loan_date,

      l.due_date,

      l.returned_at,

      l.status,

      l.renewal_count,

      l.notes,

      l.return_condition,

      l.return_notes,

      l.created_at,

      l.updated_at,

      s.full_name AS student_name,

      s.registration_number,

      s.class_id,

      c.name AS class_name,

      b.id AS book_id,

      b.title AS book_title,

      b.author AS book_author,

      b.cover_url,

      bc.inventory_code,

      u.name AS created_by_name,

      GREATEST(CURRENT_DATE - l.due_date, 0)::INT AS overdue_days,

      COALESCE(n.notice_count, 0)::INT AS notice_count

    FROM loans l

    JOIN students s ON s.id = l.student_id

    LEFT JOIN classes c ON c.id = s.class_id

    JOIN book_copies bc ON bc.id = l.copy_id

    JOIN books b ON b.id = bc.book_id

    JOIN users u ON u.id = l.created_by

    LEFT JOIN (

      SELECT loan_id, COUNT(*)::INT AS notice_count

      FROM notices

      GROUP BY loan_id

    ) n ON n.loan_id = l.id

    ORDER BY

      CASE WHEN l.status = 'active' THEN 0 ELSE 1 END,

      l.due_date,

      l.created_at DESC

  `);

  res.json({ loans: result.rows });

}));

 

app.get("/api/loans/:id", authenticate, asyncRoute(async (req, res) => {

  const loanResult = await pool.query(`

    SELECT

      l.*,

      s.full_name AS student_name,

      s.registration_number,

      c.name AS class_name,

      b.id AS book_id,

      b.title AS book_title,

      b.author AS book_author,

      b.cover_url,

      bc.inventory_code,

      u.name AS created_by_name,

      GREATEST(CURRENT_DATE - l.due_date, 0)::INT AS overdue_days

    FROM loans l

    JOIN students s ON s.id = l.student_id

    LEFT JOIN classes c ON c.id = s.class_id

    JOIN book_copies bc ON bc.id = l.copy_id

    JOIN books b ON b.id = bc.book_id

    JOIN users u ON u.id = l.created_by

    WHERE l.id = $1

  `, [req.params.id]);

 

  const loan = loanResult.rows[0];

  if (!loan) throw httpError(404, "Empréstimo não encontrado.");

 

  const notices = await pool.query(`

    SELECT n.*, u.name AS created_by_name

    FROM notices n

    JOIN users u ON u.id = n.created_by

    WHERE n.loan_id = $1

    ORDER BY n.created_at DESC

  `, [req.params.id]);

 

  res.json({ loan, notices: notices.rows });

}));

 

app.post("/api/loans", authenticate, requireRole("librarian"), asyncRoute(async (req, res) => {

  const studentId = requiredText(req.body.student_id, "o aluno");

  const bookId = requiredText(req.body.book_id, "o livro");

  const loanDate = cleanDate(req.body.loan_date, "a data do empréstimo", false);

  const dueDate = cleanDate(req.body.due_date, "a data de devolução", false);

  const notes = cleanText(req.body.notes);

  const reservationId = cleanText(req.body.reservation_id);

 

  if (new Date(`${dueDate}T00:00:00`) < new Date(`${loanDate}T00:00:00`)) {

    throw httpError(400, "A devolução não pode ser anterior ao empréstimo.");

  }

 

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

    const settings = await getSettings(client);

 

    const studentResult = await client.query(

      `SELECT id, full_name, active

       FROM students

       WHERE id = $1

       FOR UPDATE`,

      [studentId]

    );

    const student = studentResult.rows[0];

    if (!student || !student.active) throw httpError(400, "Aluno não encontrado ou arquivado.");

 

    const loanSummaryResult = await client.query(`

      SELECT

        COUNT(*) FILTER (WHERE status = 'active')::INT AS active_count,

        COUNT(*) FILTER (WHERE status = 'active' AND due_date < CURRENT_DATE)::INT AS overdue_count

      FROM loans

      WHERE student_id = $1

    `, [studentId]);

    const loanSummary = loanSummaryResult.rows[0];

 

    if (settings.block_overdue_students && loanSummary.overdue_count > 0) {

      throw httpError(409, "O aluno possui devolução atrasada e não pode receber novo empréstimo.");

    }

 

    if (loanSummary.active_count >= settings.max_active_loans) {

      throw httpError(409, `O aluno atingiu o limite de ${settings.max_active_loans} empréstimo(s) ativo(s).`);

    }

 

    const duplicateBook = await client.query(`

      SELECT 1

      FROM loans l

      JOIN book_copies bc ON bc.id = l.copy_id

      WHERE l.student_id = $1

        AND bc.book_id = $2

        AND l.status = 'active'

      LIMIT 1

    `, [studentId, bookId]);

    if (duplicateBook.rows[0]) throw httpError(409, "O aluno já está com um exemplar desse título.");

 

    const copyResult = await client.query(`

      SELECT id, inventory_code

      FROM book_copies

      WHERE book_id = $1 AND status = 'available'

      ORDER BY created_at

      LIMIT 1

      FOR UPDATE SKIP LOCKED

    `, [bookId]);

    const copy = copyResult.rows[0];

    if (!copy) throw httpError(409, "Não há exemplar disponível desse título.");

 

    const loanResult = await client.query(`

      INSERT INTO loans

        (student_id, copy_id, created_by, loan_date, due_date, status, notes)

      VALUES ($1, $2, $3, $4, $5, 'active', $6)

      RETURNING *

    `, [studentId, copy.id, req.user.id, loanDate, dueDate, notes]);

 

    await client.query(

      "UPDATE book_copies SET status = 'loaned', updated_at = NOW() WHERE id = $1",

      [copy.id]

    );

 

    if (reservationId) {

      await client.query(`

        UPDATE reservations

        SET status = 'completed', completed_at = NOW(), updated_at = NOW()

        WHERE id = $1 AND student_id = $2 AND book_id = $3

      `, [reservationId, studentId, bookId]);

    }

 

    await audit(client, req, "create", "loan", loanResult.rows[0].id, {

      student_name: student.full_name,

      student_id: studentId,

      book_id: bookId,

      copy_id: copy.id,

      inventory_code: copy.inventory_code,

      due_date: dueDate,

      reservation_id: reservationId

    });

 

    await client.query("COMMIT");

    res.status(201).json({ loan: loanResult.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.put("/api/loans/:id/return", authenticate, requireRole("librarian"), asyncRoute(async (req, res) => {

  const condition = requiredText(req.body.condition, "a condição da devolução");

  const notes = cleanText(req.body.notes);

  if (!["normal", "damaged", "lost"].includes(condition)) throw httpError(400, "Condição de devolução inválida.");

 

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

 

    const loanResult = await client.query(`

      SELECT l.*, bc.id AS locked_copy_id

      FROM loans l

      JOIN book_copies bc ON bc.id = l.copy_id

      WHERE l.id = $1

      FOR UPDATE OF l, bc

    `, [req.params.id]);

 

    const loan = loanResult.rows[0];

    if (!loan) throw httpError(404, "Empréstimo não encontrado.");

    if (loan.status !== "active") throw httpError(409, "Esse empréstimo já foi finalizado.");

 

    const loanStatus = condition === "normal" ? "returned" : condition;

    const copyStatus = condition === "normal" ? "available" : condition;

 

    const updatedLoan = await client.query(`

      UPDATE loans

      SET status = $1,

          returned_at = NOW(),

          return_condition = $2,

          return_notes = $3,

          updated_at = NOW()

      WHERE id = $4

      RETURNING *

    `, [loanStatus, condition, notes, req.params.id]);

 

    await client.query(`

      UPDATE book_copies

      SET status = $1,

          condition_notes = $2,

          updated_at = NOW()

      WHERE id = $3

    `, [copyStatus, notes, loan.copy_id]);

 

    if (copyStatus === "available") {

      const nextReservationResult = await client.query(`

        SELECT id

        FROM reservations

        WHERE book_id = (

          SELECT book_id FROM book_copies WHERE id = $1

        )

          AND status = 'active'

        ORDER BY created_at

        LIMIT 1

        FOR UPDATE SKIP LOCKED

      `, [loan.copy_id]);

 

      if (nextReservationResult.rows[0]) {

        const settings = await getSettings(client);

        await client.query(`

          UPDATE reservations

          SET status = 'ready',

              ready_at = NOW(),

              expires_at = CURRENT_DATE + $1::INT,

              updated_at = NOW()

          WHERE id = $2

        `, [settings.reservation_hold_days, nextReservationResult.rows[0].id]);

      }

    }

 

    await audit(client, req, "return", "loan", req.params.id, { condition, notes });

    await client.query("COMMIT");

    res.json({ loan: updatedLoan.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.put("/api/loans/:id/renew", authenticate, requireRole("librarian"), asyncRoute(async (req, res) => {

  const days = cleanInteger(req.body.days, { min: 1, max: 90, nullable: false });

  const client = await pool.connect();

 

  try {

    await client.query("BEGIN");

    const settings = await getSettings(client);

    const loanResult = await client.query("SELECT * FROM loans WHERE id = $1 FOR UPDATE", [req.params.id]);

    const loan = loanResult.rows[0];

 

    if (!loan) throw httpError(404, "Empréstimo não encontrado.");

    if (loan.status !== "active") throw httpError(409, "Somente empréstimos ativos podem ser renovados.");

    if (loan.renewal_count >= settings.max_renewals) {

      throw httpError(409, `O limite de ${settings.max_renewals} renovação(ões) foi atingido.`);

    }

 

    const reservation = await client.query(`

      SELECT 1

      FROM reservations r

      JOIN book_copies bc ON bc.book_id = r.book_id

      WHERE bc.id = $1

        AND r.status IN ('active', 'ready')

        AND r.student_id <> $2

      LIMIT 1

    `, [loan.copy_id, loan.student_id]);

    if (reservation.rows[0]) throw httpError(409, "O livro possui reserva de outro aluno e não pode ser renovado.");

 

    const updated = await client.query(`

      UPDATE loans

      SET due_date = GREATEST(due_date, CURRENT_DATE) + $1::INT,

          renewal_count = renewal_count + 1,

          updated_at = NOW()

      WHERE id = $2

      RETURNING *

    `, [days, req.params.id]);

 

    await audit(client, req, "renew", "loan", req.params.id, {

      days,

      new_due_date: updated.rows[0].due_date,

      renewal_count: updated.rows[0].renewal_count

    });

 

    await client.query("COMMIT");

    res.json({ loan: updated.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.get("/api/pending", authenticate, asyncRoute(async (_req, res) => {

  const result = await pool.query(`

    SELECT

      l.id,

      l.student_id,

      l.copy_id,

      l.loan_date,

      l.due_date,

      l.status,

      l.renewal_count,

      l.notes,

      s.full_name AS student_name,

      s.registration_number,

      s.guardian_contact,

      c.name AS class_name,

      b.id AS book_id,

      b.title AS book_title,

      bc.inventory_code,

      (CURRENT_DATE - l.due_date)::INT AS overdue_days,

      COALESCE(n.notice_count, 0)::INT AS notice_count,

      n.last_notice_at

    FROM loans l

    JOIN students s ON s.id = l.student_id

    LEFT JOIN classes c ON c.id = s.class_id

    JOIN book_copies bc ON bc.id = l.copy_id

    JOIN books b ON b.id = bc.book_id

    LEFT JOIN (

      SELECT loan_id, COUNT(*)::INT AS notice_count, MAX(created_at) AS last_notice_at

      FROM notices

      GROUP BY loan_id

    ) n ON n.loan_id = l.id

    WHERE l.status = 'active' AND l.due_date < CURRENT_DATE

    ORDER BY l.due_date

  `);

  res.json({ pending: result.rows });

}));

 

app.post("/api/loans/:id/notices", authenticate, requireRole("librarian"), asyncRoute(async (req, res) => {

  const channel = requiredText(req.body.channel, "o canal utilizado", 80);

  const resultLabel = requiredText(req.body.result, "o resultado do contato", 100);

  const notes = cleanText(req.body.notes);

 

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

    const loanResult = await client.query("SELECT id FROM loans WHERE id = $1", [req.params.id]);

    if (!loanResult.rows[0]) throw httpError(404, "Empréstimo não encontrado.");

 

    const result = await client.query(`

      INSERT INTO notices (loan_id, created_by, channel, result, notes)

      VALUES ($1, $2, $3, $4, $5)

      RETURNING *

    `, [req.params.id, req.user.id, channel, resultLabel, notes]);

 

    await audit(client, req, "create", "notice", result.rows[0].id, {

      loan_id: req.params.id,

      channel,

      result: resultLabel,

      notes

    });

 

    await client.query("COMMIT");

    res.status(201).json({ notice: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.get("/api/reservations", authenticate, asyncRoute(async (_req, res) => {

  await pool.query(`

    UPDATE reservations

    SET status = 'expired', updated_at = NOW()

    WHERE status = 'ready' AND expires_at < CURRENT_DATE

  `);

 

  const result = await pool.query(`

    SELECT

      r.*,

      s.full_name AS student_name,

      s.registration_number,

      c.name AS class_name,

      b.title AS book_title,

      b.author AS book_author,

      b.cover_url,

      COALESCE(inv.available_copies, 0)::INT AS available_copies,

      CASE

        WHEN r.status IN ('active', 'ready') THEN (

          SELECT COUNT(*)::INT

          FROM reservations r2

          WHERE r2.book_id = r.book_id

            AND r2.status IN ('active', 'ready')

            AND r2.created_at <= r.created_at

        )

        ELSE NULL

      END AS queue_position

    FROM reservations r

    JOIN students s ON s.id = r.student_id

    LEFT JOIN classes c ON c.id = s.class_id

    JOIN books b ON b.id = r.book_id

    LEFT JOIN (

      SELECT book_id, COUNT(*) FILTER (WHERE status = 'available')::INT AS available_copies

      FROM book_copies

      GROUP BY book_id

    ) inv ON inv.book_id = b.id

    ORDER BY

      CASE r.status WHEN 'ready' THEN 0 WHEN 'active' THEN 1 ELSE 2 END,

      r.created_at

  `);

  res.json({ reservations: result.rows });

}));

 

app.post("/api/reservations", authenticate, requireRole("librarian"), asyncRoute(async (req, res) => {

  const studentId = requiredText(req.body.student_id, "o aluno");

  const bookId = requiredText(req.body.book_id, "o livro");

  const notes = cleanText(req.body.notes);

 

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

 

    const studentResult = await client.query("SELECT id, full_name, active FROM students WHERE id = $1", [studentId]);

    if (!studentResult.rows[0] || !studentResult.rows[0].active) throw httpError(400, "Aluno não encontrado ou arquivado.");

 

    const bookResult = await client.query("SELECT id, title, active FROM books WHERE id = $1", [bookId]);

    if (!bookResult.rows[0] || !bookResult.rows[0].active) throw httpError(400, "Livro não encontrado ou arquivado.");

 

    const duplicate = await client.query(`

      SELECT 1 FROM reservations

      WHERE student_id = $1 AND book_id = $2 AND status IN ('active', 'ready')

      LIMIT 1

    `, [studentId, bookId]);

    if (duplicate.rows[0]) throw httpError(409, "O aluno já possui uma reserva ativa desse título.");

 

    const activeLoan = await client.query(`

      SELECT 1

      FROM loans l

      JOIN book_copies bc ON bc.id = l.copy_id

      WHERE l.student_id = $1 AND bc.book_id = $2 AND l.status = 'active'

      LIMIT 1

    `, [studentId, bookId]);

    if (activeLoan.rows[0]) throw httpError(409, "O aluno já está com esse título emprestado.");

 

    const result = await client.query(`

      INSERT INTO reservations (student_id, book_id, created_by, status, notes)

      VALUES ($1, $2, $3, 'active', $4)

      RETURNING *

    `, [studentId, bookId, req.user.id, notes]);

 

    await audit(client, req, "create", "reservation", result.rows[0].id, {

      student_name: studentResult.rows[0].full_name,

      book_title: bookResult.rows[0].title,

      student_id: studentId,

      book_id: bookId

    });

 

    await client.query("COMMIT");

    res.status(201).json({ reservation: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.put("/api/reservations/:id/ready", authenticate, requireRole("librarian"), asyncRoute(async (req, res) => {

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

    const settings = await getSettings(client);

 

    const reservationResult = await client.query(`

      SELECT r.*, b.title AS book_title

      FROM reservations r

      JOIN books b ON b.id = r.book_id

      WHERE r.id = $1

      FOR UPDATE

    `, [req.params.id]);

    const reservation = reservationResult.rows[0];

    if (!reservation) throw httpError(404, "Reserva não encontrada.");

    if (reservation.status !== "active") throw httpError(409, "Somente reservas aguardando podem ser marcadas como disponíveis.");

 

    const earlierReservation = await client.query(`

      SELECT id

      FROM reservations

      WHERE book_id = $1

        AND status = 'active'

        AND (created_at < $2 OR (created_at = $2 AND id::text < $3::text))

      ORDER BY created_at ASC, id ASC

      LIMIT 1

      FOR UPDATE

    `, [reservation.book_id, reservation.created_at, reservation.id]);

 

    if (earlierReservation.rows[0]) {

      throw httpError(409, "Existe outra reserva anterior na fila para este livro.");

    }

 

    const availableCopy = await client.query(

      "SELECT 1 FROM book_copies WHERE book_id = $1 AND status = 'available' LIMIT 1",

      [reservation.book_id]

    );

    if (!availableCopy.rows[0]) throw httpError(409, "Ainda não há exemplar disponível para essa reserva.");

 

    const result = await client.query(`

      UPDATE reservations

      SET status = 'ready',

          ready_at = NOW(),

          expires_at = CURRENT_DATE + $1::INT,

          updated_at = NOW()

      WHERE id = $2

      RETURNING *

    `, [settings.reservation_hold_days, req.params.id]);

 

    await audit(client, req, "ready", "reservation", req.params.id, {

      book_title: reservation.book_title,

      expires_at: result.rows[0].expires_at

    });

 

    await client.query("COMMIT");

    res.json({ reservation: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.put("/api/reservations/:id/cancel", authenticate, requireRole("librarian"), asyncRoute(async (req, res) => {

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

    const result = await client.query(`

      UPDATE reservations

      SET status = 'cancelled', cancelled_at = NOW(), updated_at = NOW()

      WHERE id = $1 AND status IN ('active', 'ready')

      RETURNING *

    `, [req.params.id]);

    if (!result.rows[0]) throw httpError(404, "Reserva ativa não encontrada.");

    await audit(client, req, "cancel", "reservation", req.params.id, result.rows[0]);

    await client.query("COMMIT");

    res.json({ reservation: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.get("/api/activity", authenticate, asyncRoute(async (req, res) => {

  const limit = cleanInteger(req.query.limit, { min: 1, max: 500 }) || 150;

  const result = await pool.query(`

    SELECT

      a.id,

      a.action,

      a.entity_type,

      a.entity_id,

      a.details,

      a.ip_address,

      a.created_at,

      u.name AS user_name,

      u.email AS user_email

    FROM audit_logs a

    LEFT JOIN users u ON u.id = a.user_id

    ORDER BY a.created_at DESC

    LIMIT $1

  `, [limit]);

  res.json({ activities: result.rows });

}));

 

app.get("/api/reports/summary", authenticate, asyncRoute(async (req, res) => {

  const today = new Date().toISOString().slice(0, 10);

  const monthStart = `${today.slice(0, 8)}01`;

  const start = cleanDate(req.query.start || monthStart, "a data inicial", false);

  const end = cleanDate(req.query.end || today, "a data final", false);

 

  if (start > end) throw httpError(400, "O período inicial não pode ser posterior ao período final.");

 

  const [loanSummary, byClass, popularBooks, losses, categories] = await Promise.all([

    pool.query(`

      SELECT

        COUNT(*)::INT AS total,

        COUNT(*) FILTER (WHERE status = 'returned')::INT AS returned,

        COUNT(*) FILTER (WHERE status = 'lost')::INT AS lost,

        COUNT(*) FILTER (WHERE status = 'damaged')::INT AS damaged

      FROM loans

      WHERE loan_date BETWEEN $1 AND $2

    `, [start, end]),

    pool.query(`

      SELECT

        c.name,

        COUNT(l.id)::INT AS loan_count

      FROM classes c

      LEFT JOIN students s ON s.class_id = c.id

      LEFT JOIN loans l ON l.student_id = s.id AND l.loan_date BETWEEN $1 AND $2

      GROUP BY c.id

      ORDER BY loan_count DESC, c.name

    `, [start, end]),

    pool.query(`

      SELECT

        b.id,

        b.title,

        b.author,

        b.cover_url,

        c.name AS category_name,

        COUNT(l.id)::INT AS loan_count

      FROM books b

      JOIN book_copies bc ON bc.book_id = b.id

      JOIN loans l ON l.copy_id = bc.id AND l.loan_date BETWEEN $1 AND $2

      LEFT JOIN categories c ON c.id = b.category_id

      GROUP BY b.id, c.id

      ORDER BY loan_count DESC, b.title

      LIMIT 20

    `, [start, end]),

    pool.query(`

      SELECT

        b.title,

        b.author,

        b.cover_url,

        bc.inventory_code,

        bc.status,

        bc.condition_notes

      FROM book_copies bc

      JOIN books b ON b.id = bc.book_id

      WHERE bc.status IN ('lost', 'damaged')

      ORDER BY b.title

    `),

    pool.query(`

      SELECT

        COALESCE(c.name, 'Sem categoria') AS name,

        COUNT(l.id)::INT AS loan_count

      FROM loans l

      JOIN book_copies bc ON bc.id = l.copy_id

      JOIN books b ON b.id = bc.book_id

      LEFT JOIN categories c ON c.id = b.category_id

      WHERE l.loan_date BETWEEN $1 AND $2

      GROUP BY c.id, c.name

      ORDER BY loan_count DESC

    `, [start, end])

  ]);

 

  res.json({

    period: { start, end },

    loans: loanSummary.rows[0],

    by_class: byClass.rows,

    popular_books: popularBooks.rows,

    losses: losses.rows,

    categories: categories.rows

  });

}));

 

app.get("/api/users", authenticate, requireRole("admin"), asyncRoute(async (_req, res) => {

  const result = await pool.query(`

    SELECT

      u.id,

      u.name,

      u.email,

      u.role,

      u.active,

      u.last_login_at,

      u.created_at,

      u.updated_at,

      u.avatar_url,

      u.phone,

      u.job_title,

      u.school_id,

      s.name AS school_name,

      COUNT(a.id)::INT AS action_count

    FROM users u

    LEFT JOIN schools s ON s.id = u.school_id

    LEFT JOIN audit_logs a ON a.user_id = u.id

    WHERE u.deleted_at IS NULL

    GROUP BY u.id, s.name

    ORDER BY u.active DESC, u.role, u.name

  `);

 

  res.json({ users: result.rows });

}));

 

app.post("/api/users", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const name = requiredText(req.body.name, "o nome", 120);

  const email = cleanEmail(req.body.email);

  const password = String(req.body.password || "");

  const role = requiredText(req.body.role || "librarian", "o perfil");

  const phone = cleanText(req.body.phone, 40);

  const jobTitle = cleanText(req.body.job_title, 80) || (role === "admin" ? "Administrador" : "Bibliotecária");

  const schoolId = cleanText(req.body.school_id, 60);

 

  if (password.length < 8) throw httpError(400, "A senha deve ter pelo menos 8 caracteres.");

  if (!["admin", "librarian"].includes(role)) throw httpError(400, "Perfil inválido.");

 

  if (schoolId) {

    const school = await pool.query(

      "SELECT id FROM schools WHERE id = $1 AND active = TRUE",

      [schoolId]

    );

    if (!school.rows[0]) throw httpError(400, "A escola selecionada não está disponível.");

  }

 

  const passwordHash = await bcrypt.hash(password, 12);

  const client = await pool.connect();

 

  try {

    await client.query("BEGIN");

 

    const result = await client.query(`

      INSERT INTO users

        (name, email, password_hash, role, active, phone, job_title, school_id)

      VALUES ($1, $2, $3, $4, TRUE, $5, $6, $7)

      RETURNING id, name, email, role, active, phone, job_title, school_id, created_at

    `, [name, email, passwordHash, role, phone, jobTitle, schoolId || null]);

 

    await audit(client, req, "create", "user", result.rows[0].id, {

      name,

      email,

      role,

      school_id: schoolId || null

    });

 

    await client.query("COMMIT");

    res.status(201).json({ user: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    if (error.code === "23505") throw httpError(409, "Já existe uma conta com esse e-mail.");

    throw error;

  } finally {

    client.release();

  }

}));

 

 

app.delete("/api/users/:id", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  if (req.params.id === req.user.id) {

    throw httpError(400, "Você não pode excluir sua própria conta.");

  }

 

  const client = await pool.connect();

 

  try {

    await client.query("BEGIN");

 

    const current = await client.query(

      `SELECT id, name, email

       FROM users

       WHERE id = $1

         AND deleted_at IS NULL`,

      [req.params.id]

    );

 

    if (!current.rows[0]) throw httpError(404, "Conta não encontrada.");

 

    const deletedEmail =

      `deleted-${req.params.id}-${Date.now()}@bookshare.invalid`;

 

    await client.query(`

      UPDATE users

      SET active = FALSE,

          deleted_at = NOW(),

          email = $1,

          updated_at = NOW()

      WHERE id = $2

    `, [deletedEmail, req.params.id]);

 

    await audit(client, req, "delete", "user", req.params.id, {

      name: current.rows[0].name,

      email: current.rows[0].email

    });

 

    await client.query("COMMIT");

    res.json({ message: "Conta excluída." });

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.put("/api/users/:id/status", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const active = cleanBoolean(req.body.active);

  if (req.params.id === req.user.id && !active) throw httpError(400, "Você não pode bloquear sua própria conta.");

 

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

    const result = await client.query(`

      UPDATE users SET active = $1, updated_at = NOW()

      WHERE id = $2

      RETURNING id, name, email, role, active

    `, [active, req.params.id]);

    if (!result.rows[0]) throw httpError(404, "Usuário não encontrado.");

    await audit(client, req, active ? "reactivate" : "block", "user", req.params.id, { active, name: result.rows[0].name });

    await client.query("COMMIT");

    res.json({ user: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.put("/api/users/:id/password", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const password = String(req.body.password || "");

  if (password.length < 8) throw httpError(400, "A senha deve ter pelo menos 8 caracteres.");

 

  const passwordHash = await bcrypt.hash(password, 12);

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

    const result = await client.query(`

      UPDATE users SET password_hash = $1, updated_at = NOW()

      WHERE id = $2

      RETURNING id, name

    `, [passwordHash, req.params.id]);

    if (!result.rows[0]) throw httpError(404, "Usuário não encontrado.");

    await audit(client, req, "password", "user", req.params.id, { name: result.rows[0].name, reset_by_admin: true });

    await client.query("COMMIT");

    res.json({ message: "Senha atualizada." });

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.get("/api/settings", authenticate, asyncRoute(async (_req, res) => {

  res.json({ settings: await getSettings() });

}));

 

app.put("/api/settings", authenticate, requireRole("admin"), asyncRoute(async (req, res) => {

  const schoolName = requiredText(req.body.school_name, "o nome da escola", 120);

  const libraryName = requiredText(req.body.library_name, "o nome da biblioteca", 120);

  const contactEmail = cleanText(req.body.contact_email, 180);

  const contactPhone = cleanText(req.body.contact_phone, 40);

  const currentSchoolYear = cleanInteger(req.body.current_school_year, { min: 2020, max: 2100, nullable: false });

  const defaultLoanDays = cleanInteger(req.body.default_loan_days, { min: 1, max: 90, nullable: false });

  const maxActiveLoans = cleanInteger(req.body.max_active_loans, { min: 1, max: 20, nullable: false });

  const maxRenewals = cleanInteger(req.body.max_renewals, { min: 0, max: 10, nullable: false });

  const renewalDays = cleanInteger(req.body.renewal_days, { min: 1, max: 90, nullable: false });

  const dueSoonDays = cleanInteger(req.body.due_soon_days, { min: 0, max: 30, nullable: false });

  const reservationHoldDays = cleanInteger(req.body.reservation_hold_days, { min: 1, max: 30, nullable: false });

  const blockOverdueStudents = cleanBoolean(req.body.block_overdue_students, true);

  const noticeTemplate = requiredText(req.body.notice_template, "o modelo de cobrança");

  const reservationTemplate = requiredText(req.body.reservation_template, "o modelo de reserva");

 

  const client = await pool.connect();

  try {

    await client.query("BEGIN");

    const result = await client.query(`

      UPDATE settings

      SET school_name = $1,

          library_name = $2,

          contact_email = $3,

          contact_phone = $4,

          current_school_year = $5,

          default_loan_days = $6,

          max_active_loans = $7,

          max_renewals = $8,

          renewal_days = $9,

          due_soon_days = $10,

          reservation_hold_days = $11,

          block_overdue_students = $12,

          notice_template = $13,

          reservation_template = $14,

          updated_at = NOW()

      WHERE id = 1

      RETURNING *

    `, [

      schoolName,

      libraryName,

      contactEmail,

      contactPhone,

      currentSchoolYear,

      defaultLoanDays,

      maxActiveLoans,

      maxRenewals,

      renewalDays,

      dueSoonDays,

      reservationHoldDays,

      blockOverdueStudents,

      noticeTemplate,

      reservationTemplate

    ]);

 

    await audit(client, req, "update", "settings", "1", result.rows[0]);

    await client.query("COMMIT");

    res.json({ settings: result.rows[0] });

  } catch (error) {

    await client.query("ROLLBACK");

    throw error;

  } finally {

    client.release();

  }

}));

 

app.use((_req, res) => {

  res.status(404).json({ message: "Rota não encontrada." });

});

 

app.use((error, _req, res, _next) => {

  console.error(error);

 

  if (error.message === "Origem não autorizada pelo CORS.") {

    return res.status(403).json({ message: error.message });

  }

 

  if (error.code === "22P02") {

    return res.status(400).json({ message: "Um dos identificadores enviados é inválido." });

  }

 

  if (error.code === "23503") {

    return res.status(409).json({ message: "Esse registro está vinculado a outras informações do sistema." });

  }

 

  if (error.code === "23514") {

    return res.status(400).json({ message: "Um dos valores enviados não atende às regras do banco." });

  }

 

  const status = error.status || 500;

  return res.status(status).json({

    message: status === 500

      ? "Erro interno do servidor. Consulte os logs do Render."

      : error.message

  });

});

 

 

async function clearUnverifiedBookCovers() {

  const result = await pool.query(`

    UPDATE books

    SET cover_url = NULL,

        cover_source = NULL,

        cover_checked_at = NULL,

        updated_at = NOW()

    WHERE COALESCE(cover_source, '') <> 'manual-upload'

      AND (

        cover_url LIKE 'data:image/svg+xml%'

        OR cover_url ILIKE '%image_not_available%'

        OR cover_url ILIKE '%no_cover%'

        OR cover_source IN (

          'official-not-found',

          'broken',

          'not-found',

          'fixed-original-v22'

        )

      )

  `);

 

  console.log(`Capas antigas ou inválidas removidas: ${result.rowCount}.`);

}

 

async function start() {

  try {

    await pool.query("SELECT 1");

    await ensureRuntimeSchema();

    await ensureInitialUsers();

    await primeCoverPlaceholderHashes();

    await clearUnverifiedBookCovers();

 

    app.listen(PORT, () => {

      console.log(`BookShare API 9.2 online na porta ${PORT}.`);

 

      setTimeout(() => {

        syncBookCovers({ force: true })

          .catch(error => console.error("Falha na sincronização das capas originais:", error));

      }, 3000);

    });

  } catch (error) {

    if (error?.code === "28P01") {

      console.error("Falha ao iniciar a API: usuário ou senha do Supabase incorretos.");

      console.error("Use no Render a DATABASE_URL do Session Pooler, com usuário postgres.REFERENCIA_DO_PROJETO.");

      console.error("Redefina a Database password no Supabase e copie novamente a URI do Session Pooler.");

    } else if (error?.code === "ENETUNREACH") {

      console.error("Use o Session Pooler IPv4 do Supabase em vez da conexão direta IPv6.");

    }

    console.error("Detalhes técnicos:", error);

    process.exit(1);

  }

}

 

start();
