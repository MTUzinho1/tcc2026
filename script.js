// Nossos dados (simulando um banco de dados)
let books = [
    { id: 1, title: "Igreja Medieval", author: "Leandro Duarte Rust", status: "Lido", cover: "https://m.media-amazon.com/images/I/81+H-wA-25L.jpg", loanedTo: null },
    { id: 2, title: "Minha vida secreta na Máfia", author: "Joseph D. Pistone", status: "Lendo", cover: "https://static.estantevirtual.com.br/book/00/1D1-4881-000/1D1-4881-000_detail1.jpg", loanedTo: null },
    { id: 3, title: "Mestres do mistério", author: "Edgar Allan Poe", status: "Lido", cover: "https://martinsfontespaulista.vteximg.com.br/arquivos/ids/1458823-292-292/986695.jpg", loanedTo: null }
];

// Alternar entre Login e Cadastro
function toggleAuth() {
    document.getElementById('login-box').classList.toggle('hidden');
    document.getElementById('register-box').classList.toggle('hidden');
}

// Entrar no sistema
function showApp() {
    document.getElementById('auth-container').classList.add('hidden');
    document.getElementById('main-app').classList.remove('hidden');
    renderBooks();
}

// Desenhar os livros na tela
function renderBooks() {
    const grid = document.getElementById('bookGrid');
    grid.innerHTML = '';

    books.forEach(book => {
        const isLoaned = book.loanedTo !== null;
        grid.innerHTML += `
            <div class="book-card">
                <div class="book-cover" style="background-image: url('${book.cover}')"></div>
                <div class="book-info">
                    <h4>${book.title}</h4>
                    <span class="status-badge ${isLoaned ? 'status-loaned' : 'status-read'}">
                        ${isLoaned ? 'Emprestado' : 'Na Estante'}
                    </span>
                    <button class="btn-loan" onclick="handleLoan(${book.id})">
                        ${isLoaned ? 'Devolver' : 'Emprestar'}
                    </button>
                </div>
            </div>
        `;
    });
}

// Lógica de Empréstimo
function handleLoan(id) {
    const book = books.find(b => b.id === id);
    if (book.loanedTo) {
        book.loanedTo = null; // Devolve o livro
    } else {
        const name = prompt("Para quem você está emprestando este livro?");
        if (name) book.loanedTo = name;
    }
    renderBooks();
}

// Logout
function logout() { location.reload(); }
