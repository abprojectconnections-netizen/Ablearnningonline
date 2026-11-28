package community

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/ablearning/api/internal/platform"
)

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) RegisterRoutes(mux *http.ServeMux, protected func(http.Handler) http.Handler) {
	mux.Handle("GET /api/v1/community/posts", protected(http.HandlerFunc(h.feed)))
	mux.Handle("POST /api/v1/community/posts", protected(http.HandlerFunc(h.create)))
	mux.Handle("DELETE /api/v1/community/posts/{id}", protected(http.HandlerFunc(h.delete)))
	mux.Handle("POST /api/v1/community/posts/{id}/like", protected(http.HandlerFunc(h.like)))
	mux.Handle("DELETE /api/v1/community/posts/{id}/like", protected(http.HandlerFunc(h.unlike)))
	mux.Handle("GET /api/v1/community/posts/{id}/comments", protected(http.HandlerFunc(h.comments)))
	mux.Handle("POST /api/v1/community/posts/{id}/comments", protected(http.HandlerFunc(h.comment)))
}

func mapError(err error) error {
	switch {
	case errors.Is(err, ErrInvalid):
		return platform.ErrValidation("content must not be empty and must fit the length limit")
	case errors.Is(err, ErrNotFound):
		return platform.ErrNotFound(err.Error())
	case errors.Is(err, ErrForbidden):
		return platform.Forbidden(err.Error())
	default:
		return err
	}
}

// ids reads the caller and, when withPost is set, the {id} path value.
func ids(w http.ResponseWriter, r *http.Request, withPost bool) (int64, int64, bool) {
	userID, ok := platform.UserIDFromContext(r.Context())
	if !ok {
		platform.WriteError(w, platform.ErrUnauthorized)
		return 0, 0, false
	}
	if !withPost {
		return userID, 0, true
	}
	postID, err := platform.ParseID(r.PathValue("id"), "post")
	if err != nil {
		platform.WriteError(w, err)
		return 0, 0, false
	}
	return userID, postID, true
}

type contentRequest struct {
	Content string `json:"content"`
}

func (h *Handler) feed(w http.ResponseWriter, r *http.Request) {
	userID, _, ok := ids(w, r, false)
	if !ok {
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	page, err := h.svc.Feed(r.Context(), userID, limit, offset)
	if err != nil {
		platform.WriteError(w, err)
		return
	}
	platform.WriteJSON(w, http.StatusOK, page)
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	userID, _, ok := ids(w, r, false)
	if !ok {
		return
	}
	var req contentRequest
	if err := platform.DecodeJSON(r, &req); err != nil {
		platform.WriteError(w, err)
		return
	}
	post, err := h.svc.Create(r.Context(), userID, req.Content)
	if err != nil {
		platform.WriteError(w, mapError(err))
		return
	}
	platform.WriteJSON(w, http.StatusCreated, post)
}

func (h *Handler) delete(w http.ResponseWriter, r *http.Request) {
	userID, postID, ok := ids(w, r, true)
	if !ok {
		return
	}
	if err := h.svc.Delete(r.Context(), userID, postID); err != nil {
		platform.WriteError(w, mapError(err))
		return
	}
	platform.WriteJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (h *Handler) setLike(w http.ResponseWriter, r *http.Request, liked bool) {
	userID, postID, ok := ids(w, r, true)
	if !ok {
		return
	}
	post, err := h.svc.Like(r.Context(), userID, postID, liked)
	if err != nil {
		platform.WriteError(w, mapError(err))
		return
	}
	platform.WriteJSON(w, http.StatusOK, post)
}

func (h *Handler) like(w http.ResponseWriter, r *http.Request)   { h.setLike(w, r, true) }
func (h *Handler) unlike(w http.ResponseWriter, r *http.Request) { h.setLike(w, r, false) }

func (h *Handler) comments(w http.ResponseWriter, r *http.Request) {
	userID, postID, ok := ids(w, r, true)
	if !ok {
		return
	}
	items, err := h.svc.Comments(r.Context(), userID, postID)
	if err != nil {
		platform.WriteError(w, mapError(err))
		return
	}
	platform.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (h *Handler) comment(w http.ResponseWriter, r *http.Request) {
	userID, postID, ok := ids(w, r, true)
	if !ok {
		return
	}
	var req contentRequest
	if err := platform.DecodeJSON(r, &req); err != nil {
		platform.WriteError(w, err)
		return
	}
	items, err := h.svc.Comment(r.Context(), userID, postID, req.Content)
	if err != nil {
		platform.WriteError(w, mapError(err))
		return
	}
	platform.WriteJSON(w, http.StatusCreated, map[string]any{"items": items})
}
