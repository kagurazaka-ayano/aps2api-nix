package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"unicode"
)

func main() {
	url := os.Args[1]
	resp, err := http.Get(url)
	if err != nil {
		panic(err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		panic(err)
	}
	rulesText := string(data)
	cleanText := strings.Map(func(r rune) rune {
		if unicode.IsSpace(r) {
			return -1
		}
		return r
	}, rulesText)
	sum := sha256.Sum256([]byte(cleanText))
	fmt.Println(hex.EncodeToString(sum[:])[:16])
}
