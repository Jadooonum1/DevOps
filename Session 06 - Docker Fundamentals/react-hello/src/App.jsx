import { useState } from "react";

const shelf = ["Dune", "The Hobbit", "Pride and Prejudice"];

export default function App() {
  const [count, setCount] = useState(0);
  return (
    <main style={{ fontFamily: "sans-serif", padding: "2rem" }}>
      <h1>Hello World from the Bookshelf (React + Vite)</h1>
      <p>Built in a Node stage, served as static files by nginx.</p>
      <ul>
        {shelf.map((title) => (
          <li key={title}>{title}</li>
        ))}
      </ul>
      <button onClick={() => setCount(count + 1)}>Books borrowed: {count}</button>
    </main>
  );
}
