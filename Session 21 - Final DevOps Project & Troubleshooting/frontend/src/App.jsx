import { useEffect, useState } from "react";

async function api(path, options = {}) {
  const res = await fetch(`/api${path}`, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  return res.status === 204 ? null : res.json();
}

export default function App() {
  const [books, setBooks] = useState([]);
  const [title, setTitle] = useState("");
  const [author, setAuthor] = useState("");
  const [error, setError] = useState("");

  const refresh = () => api("/books").then(setBooks).catch((e) => setError(e.message));
  useEffect(() => { refresh(); }, []);

  const run = (promise) => promise.then(refresh).then(() => setError("")).catch((e) => setError(e.message));

  const add = (e) => {
    e.preventDefault();
    run(api("/books", { method: "POST", body: JSON.stringify({ title, author }) }));
    setTitle("");
    setAuthor("");
  };

  return (
    <main>
      <h1>Bookshelf</h1>
      <form onSubmit={add}>
        <input placeholder="Title" value={title} onChange={(e) => setTitle(e.target.value)} required />
        <input placeholder="Author" value={author} onChange={(e) => setAuthor(e.target.value)} required />
        <button type="submit">Add book</button>
      </form>
      {error && <p className="error">{error}</p>}
      <table>
        <thead>
          <tr><th>#</th><th>Title</th><th>Author</th><th>Status</th><th></th></tr>
        </thead>
        <tbody>
          {books.map((b) => (
            <tr key={b.id}>
              <td>{b.id}</td>
              <td>{b.title}</td>
              <td>{b.author}</td>
              <td>{b.on_loan ? "On loan" : "Available"}</td>
              <td>
                <button onClick={() => run(api(`/books/${b.id}/${b.on_loan ? "return" : "borrow"}`, { method: "POST" }))}>
                  {b.on_loan ? "Return" : "Borrow"}
                </button>
                <button onClick={() => run(api(`/books/${b.id}`, { method: "DELETE" }))}>Delete</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      {books.length === 0 && <p>No books yet - add one above.</p>}
    </main>
  );
}
