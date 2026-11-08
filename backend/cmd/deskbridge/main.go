package main

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/naladwepo/zapret-for-mac/internal/ctl"
	"io"
	"os"
	"time"
)

func main() {
	var req ctl.Request
	b, err := io.ReadAll(io.LimitReader(os.Stdin, 1<<20))
	if err == nil {
		err = json.Unmarshal(b, &req)
	}
	if err != nil {
		fail(err)
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 95*time.Second)
	defer cancel()
	resp, err := ctl.NewClient("").WithTimeout(95*time.Second).Do(ctx, req)
	if err != nil {
		fail(err)
		return
	}
	json.NewEncoder(os.Stdout).Encode(resp)
}
func fail(err error) {
	json.NewEncoder(os.Stdout).Encode(map[string]any{"ok": false, "error": fmt.Sprint(err)})
}
