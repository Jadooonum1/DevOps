// catalog-api: a tiny book catalogue service used to demonstrate multi-stage builds.
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"runtime"
)

type Book struct {
	ISBN   string `json:"isbn"`
	Title  string `json:"title"`
	Author string `json:"author"`
}

var catalog = []Book{
	{"9780441013593", "Dune", "Frank Herbert"},
	{"9780547928227", "The Hobbit", "J.R.R. Tolkien"},
	{"9780141439518", "Pride and Prejudice", "Jane Austen"},
}

func main() {
	host, _ := os.Hostname()

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Write([]byte("catalog-api built with " + runtime.Version() + ", running in container " + host + "\n"))
	})
	http.HandleFunc("/books", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(catalog)
	})
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok\n"))
	})

	log.Println("catalog-api listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
