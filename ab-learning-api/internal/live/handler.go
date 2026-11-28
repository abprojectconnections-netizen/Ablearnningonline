package live

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/ablearning/api/internal/platform"
)

type Handler struct {
	svc      *Service
	askLimit func(http.Handler) http.Handler
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc, askLimit: platform.RateLimitByUser(QuestionsPerMin, time.Minute)}
}

func (h *Handler) RegisterRoutes(mux *http.ServeMux, protected func(http.Handler) http.Handler) {
	p := func(f http.HandlerFunc) http.Handler { return protected(f) }
	inst := func(f http.HandlerFunc) http.Handler {
		return protected(platform.RequireRole("INSTRUCTOR")(f))
	}
	mux.Handle("GET /api/v1/live", p(h.list))
	mux.Handle("GET /api/v1/live/{id}", p(h.detail))
	mux.Handle("POST /api/v1/live/{id}/register", p(h.register))
	mux.Handle("DELETE /api/v1/live/{id}/register", p(h.unregister))
	mux.Handle("POST /api/v1/live/{id}/questions", protected(h.askLimit(http.HandlerFunc(h.ask))))
	mux.Handle("POST /api/v1/live/questions/{id}/upvote", p(h.upvote))
	mux.Handle("DELETE /api/v1/live/questions/{id}/upvote", p(h.unvote))

	mux.Handle("GET /api/v1/instructor/live", inst(h.mine))
	mux.Handle("POST /api/v1/instructor/live", inst(h.schedule))
	mux.Handle("PATCH /api/v1/instructor/live/{id}/status", inst(h.status))
	mux.Handle("POST /api/v1/instructor/live/questions/{id}/answered", inst(h.answered))
}

func mapError(err error) error {
	switch {
	case errors.Is(err, ErrInvalid):
		return platform.ErrValidation("check the title, a future scheduled_at (RFC3339), 15-480 minutes and http(s) links")
	case errors.Is(err, ErrNotFound):
		return platform.ErrNotFound(err.Error())
	case errors.Is(err, ErrNotRegistered), errors.Is(err, ErrNotInstructor), errors.Is(err, ErrNotOwner):
		return platform.Forbidden(err.Error())
	case errors.Is(err, ErrClosed), errors.Is(err, ErrPaid), errors.Is(err, ErrTransition):
		return platform.NewAppError(http.StatusConflict, "CONFLICT", err.Error())
	default:
		return err
	}
}

// withID runs fn with the caller and the {id} path value.
func withID(w http.ResponseWriter, r *http.Request, name string, fn func(ctx context.Context, userID, id int64) (any, error)) {
	userID, ok := platform.UserIDFromContext(r.Context())
	if !ok {
		platform.WriteError(w, platform.ErrUnauthorized)
		return
	}
	id, err := platform.ParseID(r.PathValue("id"), name)
	if err != nil {
		platform.WriteError(w, err)
		return
	}
	out, err := fn(r.Context(), userID, id)
	if err != nil {
		platform.WriteError(w, mapError(err))
		return
	}
	platform.WriteJSON(w, http.StatusOK, out)
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	userID, ok := platform.UserIDFromContext(r.Context())
	if !ok {
		platform.WriteError(w, platform.ErrUnauthorized)
		return
	}
	items, err := h.svc.List(r.Context(), userID, r.URL.Query().Get("scope") == "past")
	if err != nil {
		platform.WriteError(w, err)
		return
	}
	platform.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (h *Handler) detail(w http.ResponseWriter, r *http.Request) {
	withID(w, r, "live session", func(ctx context.Context, u, id int64) (any, error) { return h.svc.Detail(ctx, u, id) })
}

func (h *Handler) register(w http.ResponseWriter, r *http.Request) {
	withID(w, r, "live session", func(ctx context.Context, u, id int64) (any, error) { return h.svc.Register(ctx, u, id, true) })
}

func (h *Handler) unregister(w http.ResponseWriter, r *http.Request) {
	withID(w, r, "live session", func(ctx context.Context, u, id int64) (any, error) { return h.svc.Register(ctx, u, id, false) })
}

func (h *Handler) ask(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Question string `json:"question"`
	}
	if err := platform.DecodeJSON(r, &req); err != nil {
		platform.WriteError(w, err)
		return
	}
	withID(w, r, "live session", func(ctx context.Context, u, id int64) (any, error) { return h.svc.Ask(ctx, u, id, req.Question) })
}

func (h *Handler) upvote(w http.ResponseWriter, r *http.Request) {
	withID(w, r, "question", func(ctx context.Context, u, id int64) (any, error) { return h.svc.Vote(ctx, u, id, true) })
}

func (h *Handler) unvote(w http.ResponseWriter, r *http.Request) {
	withID(w, r, "question", func(ctx context.Context, u, id int64) (any, error) { return h.svc.Vote(ctx, u, id, false) })
}

func (h *Handler) mine(w http.ResponseWriter, r *http.Request) {
	userID, _ := platform.UserIDFromContext(r.Context())
	items, err := h.svc.Mine(r.Context(), userID)
	if err != nil {
		platform.WriteError(w, mapError(err))
		return
	}
	platform.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (h *Handler) schedule(w http.ResponseWriter, r *http.Request) {
	userID, _ := platform.UserIDFromContext(r.Context())
	var in NewSession
	if err := platform.DecodeJSON(r, &in); err != nil {
		platform.WriteError(w, err)
		return
	}
	out, err := h.svc.Schedule(r.Context(), userID, in)
	if err != nil {
		platform.WriteError(w, mapError(err))
		return
	}
	platform.WriteJSON(w, http.StatusCreated, out)
}

func (h *Handler) status(w http.ResponseWriter, r *http.Request) {
	var c StatusChange
	if err := platform.DecodeJSON(r, &c); err != nil {
		platform.WriteError(w, err)
		return
	}
	withID(w, r, "live session", func(ctx context.Context, u, id int64) (any, error) { return h.svc.ChangeStatus(ctx, u, id, c) })
}

func (h *Handler) answered(w http.ResponseWriter, r *http.Request) {
	withID(w, r, "question", func(ctx context.Context, u, id int64) (any, error) { return h.svc.Answer(ctx, u, id) })
}
