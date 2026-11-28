package platform

import (
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

type rateWindow struct {
	start time.Time
	count int
}

type clientLimiter struct {
	mu      sync.Mutex
	clients map[string]rateWindow
	limit   int
	window  time.Duration
}

func RateLimit(limit int, window time.Duration) func(http.Handler) http.Handler {
	limiter := &clientLimiter{
		clients: make(map[string]rateWindow),
		limit:   limit,
		window:  window,
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if !limiter.allow(clientIP(r), time.Now()) {
				WriteError(w, NewAppError(http.StatusTooManyRequests, "RATE_LIMITED", "Too many requests. Please try again later."))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func (l *clientLimiter) allow(ip string, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	if len(l.clients) > 10000 {
		for key, entry := range l.clients {
			if now.Sub(entry.start) >= l.window {
				delete(l.clients, key)
			}
		}
	}
	entry := l.clients[ip]
	if now.Sub(entry.start) >= l.window {
		entry = rateWindow{start: now}
	}
	if entry.count >= l.limit {
		return false
	}
	entry.count++
	l.clients[ip] = entry
	return true
}

func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return strings.TrimSpace(r.RemoteAddr)
}

// RateLimitByUser limits each signed-in user separately. It must run inside
// RequireAuth so the user id is in the context; anonymous calls fall back to
// the client IP.
func RateLimitByUser(limit int, window time.Duration) func(http.Handler) http.Handler {
	limiter := &clientLimiter{
		clients: make(map[string]rateWindow),
		limit:   limit,
		window:  window,
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			key := "ip:" + clientIP(r)
			if id, ok := UserIDFromContext(r.Context()); ok {
				key = "user:" + strconv.FormatInt(id, 10)
			}
			if !limiter.allow(key, time.Now()) {
				WriteError(w, NewAppError(http.StatusTooManyRequests, "RATE_LIMITED", "You are doing that too often. Please wait a moment."))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
