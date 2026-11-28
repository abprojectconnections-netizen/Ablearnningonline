package community

import "context"

type Service struct{ repo Repository }

func NewService(repo Repository) *Service { return &Service{repo: repo} }

func (s *Service) Feed(ctx context.Context, viewerID int64, limit, offset int) (*Page, error) {
	limit, offset = clampPaging(limit, offset)
	items, err := s.repo.ListPosts(ctx, viewerID, limit, offset)
	if err != nil {
		return nil, err
	}
	if items == nil {
		items = []Post{}
	}
	return &Page{Items: items, Limit: limit, Offset: offset}, nil
}

func (s *Service) Create(ctx context.Context, userID int64, content string) (Post, error) {
	content, err := clean(content, MaxPost)
	if err != nil {
		return Post{}, err
	}
	id, err := s.repo.CreatePost(ctx, userID, content)
	if err != nil {
		return Post{}, err
	}
	return s.repo.GetPost(ctx, userID, id)
}

func (s *Service) Delete(ctx context.Context, userID, postID int64) error {
	return s.repo.DeletePost(ctx, userID, postID)
}

func (s *Service) Like(ctx context.Context, userID, postID int64, liked bool) (Post, error) {
	if err := s.repo.SetLike(ctx, userID, postID, liked); err != nil {
		return Post{}, err
	}
	return s.repo.GetPost(ctx, userID, postID)
}

func (s *Service) Comments(ctx context.Context, viewerID, postID int64) ([]Comment, error) {
	if _, err := s.repo.GetPost(ctx, viewerID, postID); err != nil {
		return nil, err
	}
	items, err := s.repo.ListComments(ctx, viewerID, postID)
	if items == nil && err == nil {
		items = []Comment{}
	}
	return items, err
}

func (s *Service) Comment(ctx context.Context, userID, postID int64, content string) ([]Comment, error) {
	content, err := clean(content, MaxComment)
	if err != nil {
		return nil, err
	}
	if _, err := s.repo.AddComment(ctx, userID, postID, content); err != nil {
		return nil, err
	}
	return s.Comments(ctx, userID, postID)
}
