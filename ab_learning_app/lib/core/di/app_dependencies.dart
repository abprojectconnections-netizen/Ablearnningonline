import '../../features/auth/data/account_repository.dart';
import '../../features/catalog/data/catalog_repository.dart';
import '../../features/certificates/data/certificates_repository.dart';
import '../../features/checkout/data/orders_repository.dart';
import '../../features/explore/data/explore_repository.dart';
import '../../features/learn/data/learn_repository.dart';
import '../../features/notifications/data/notifications_repository.dart';
import '../../features/quiz/data/quiz_repository.dart';
import '../../features/reviews/data/reviews_repository.dart';
import '../../features/tutor/data/tutor_repository.dart';
import '../../features/wallet/data/wallet_repository.dart';
import '../network/rest_client.dart';
import '../network/api_config.dart';
import '../network/token_store.dart';

/// Minimal service locator (the app does not use Riverpod providers yet).
/// Tests replace repositories with fakes and call [reset] afterwards.
class AppDependencies {
  static RestClient? _client;
  static AccountRepository? _auth;
  static TutorRepository? _tutor;
  static CatalogRepository? _catalog;
  static OrdersRepository? _orders;
  static NotificationsRepository? _notifications;
  static WalletRepository? _wallet;
  static ReviewsRepository? _reviews;
  static LearnRepository? _learn;
  static ExploreRepository? _explore;
  static QuizRepository? _quiz;
  static CertificatesRepository? _certificates;

  /// One client (and token store) shared by every API repository.
  static RestClient get apiClient =>
      _client ??= RestClient(tokenStore: SecureTokenStore());

  static AccountRepository get authRepository => _auth ??= ApiConfig.useMockAuth
      ? MockAccountRepository()
      : ApiAccountRepository(apiClient);

  static set authRepository(AccountRepository value) => _auth = value;

  static TutorRepository get tutorRepository => _tutor ??= ApiConfig.useMockAuth
      ? MockTutorRepository()
      : ApiTutorRepository(apiClient);

  static set tutorRepository(TutorRepository value) => _tutor = value;

  static CatalogRepository get catalogRepository =>
      _catalog ??= ApiConfig.useMockAuth
          ? const OfflineCatalogRepository()
          : ApiCatalogRepository(apiClient);

  static set catalogRepository(CatalogRepository value) => _catalog = value;

  static OrdersRepository get ordersRepository =>
      _orders ??= ApiConfig.useMockAuth
          ? const OfflineOrdersRepository()
          : ApiOrdersRepository(apiClient);

  static set ordersRepository(OrdersRepository value) => _orders = value;

  static NotificationsRepository get notificationsRepository =>
      _notifications ??= ApiConfig.useMockAuth
          ? const OfflineNotificationsRepository()
          : ApiNotificationsRepository(apiClient);

  static set notificationsRepository(NotificationsRepository value) =>
      _notifications = value;

  static WalletRepository get walletRepository =>
      _wallet ??= ApiConfig.useMockAuth
          ? const OfflineWalletRepository()
          : ApiWalletRepository(apiClient);

  static set walletRepository(WalletRepository value) => _wallet = value;

  static ReviewsRepository get reviewsRepository =>
      _reviews ??= ApiConfig.useMockAuth
          ? const OfflineReviewsRepository()
          : ApiReviewsRepository(apiClient);

  static set reviewsRepository(ReviewsRepository value) => _reviews = value;

  static LearnRepository get learnRepository => _learn ??= ApiConfig.useMockAuth
      ? const OfflineLearnRepository()
      : ApiLearnRepository(apiClient);

  static set learnRepository(LearnRepository value) => _learn = value;

  static ExploreRepository get exploreRepository =>
      _explore ??= ApiConfig.useMockAuth
          ? const OfflineExploreRepository()
          : ApiExploreRepository(apiClient);

  static set exploreRepository(ExploreRepository value) => _explore = value;

  /// Only used for lessons that live on the server; the bundled demo quiz
  /// never calls it, so there is no offline variant.
  static QuizRepository get quizRepository =>
      _quiz ??= ApiQuizRepository(apiClient);

  static set quizRepository(QuizRepository value) => _quiz = value;

  static CertificatesRepository get certificatesRepository =>
      _certificates ??= ApiConfig.useMockAuth
          ? const OfflineCertificatesRepository()
          : ApiCertificatesRepository(apiClient);

  static set certificatesRepository(CertificatesRepository value) =>
      _certificates = value;

  static void reset() {
    _client = null;
    _auth = null;
    _tutor = null;
    _catalog = null;
    _orders = null;
    _notifications = null;
    _wallet = null;
    _reviews = null;
    _learn = null;
    _explore = null;
    _quiz = null;
    _certificates = null;
  }
}
