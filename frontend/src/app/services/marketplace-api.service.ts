import { HttpClient, HttpHeaders, HttpParams } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable, from, switchMap, throwError } from 'rxjs';
import { catchError } from 'rxjs/operators';

import { environment } from '../../environments/environment';
import { OfflineStorageService } from './offline-storage.service';

export interface SessionUser {
  id: string;
  email: string;
  role: 'client' | 'worker' | 'agency' | 'admin';
  fullName?: string;
  status?: string;
}

export interface AuthResponse {
  token: string;
  user: SessionUser;
}

export interface RegisterResponse {
  user: SessionUser;
  emailVerificationRequired: boolean;
  devVerificationCode?: string;
}

export interface ResendVerificationResponse {
  emailVerificationRequired?: boolean;
  emailVerified?: boolean;
  devVerificationCode?: string;
}

export interface ProviderProfile {
  userId: string;
  role: 'worker' | 'agency' | 'admin';
  displayName: string;
  category: string;
  municipality: string;
  services: string[];
  portfolio: Array<{ title: string; imageUrl?: string; description?: string }>;
  reviewSummary?: { providerUserId: string; count: number; average: number };
}

export interface SearchResponse {
  profiles: ProviderProfile[];
  filters: { category: string; municipality: string; service: string };
  cache: { source: 'mongo' | 'redis' | 'local'; hit: boolean };
}

export interface Category {
  id: string;
  name: string;
  slug: string;
  description: string;
  icon: string;
  active: boolean;
}

export interface ServiceListing {
  id: string;
  providerUserId: string;
  providerRole: 'worker' | 'agency' | 'admin';
  providerDisplayName?: string;
  title: string;
  category: string;
  municipality: string;
  description: string;
  priceMin: number;
  priceMax: number;
  estimatedDuration: string;
  requirements: string[];
  availability: string[];
  media: Array<{ imageUrl: string; caption?: string }>;
  status: 'active';
  reviewSummary?: { providerUserId: string; count: number; average: number };
}

export interface ProviderDetailResponse {
  provider: SessionUser;
  profile: ProviderProfile | null;
  serviceListings: ServiceListing[];
  reviews: Array<{ id: string; rating: number; comment: string; createdAt: string }>;
  reviewSummary: { count: number; average: number };
}

export interface BookingPayload {
  providerUserId: string;
  serviceListingId?: string;
  serviceCategory: string;
  municipality: string;
  locationDetails?: string;
  notes: string;
  scheduledAt?: string;
}

export interface Booking {
  id: string;
  clientUserId: string;
  providerUserId: string;
  serviceListingId?: string;
  serviceCategory: string;
  municipality: string;
  locationDetails: string;
  notes: string;
  scheduledAt?: string;
  previousStatus?: string;
  providerCompletedAt?: string;
  clientConfirmedAt?: string;
  cancellationRequestedAt?: string;
  cancellationRequestedBy?: string;
  status: 'pending' | 'accepted' | 'in_progress' | 'completion_requested' | 'completed' | 'rejected' | 'cancellation_requested' | 'cancelled';
  createdAt: string;
  updatedAt: string;
}

export interface Conversation {
  id: string;
  clientUserId: string;
  clientName?: string;
  providerUserId: string;
  providerName?: string;
  serviceListingId?: string;
  bookingId?: string;
  lastMessagePreview: string;
  createdAt: string;
  updatedAt: string;
}

export interface ConversationMessage {
  id: string;
  conversationId: string;
  senderUserId: string;
  message: string;
  createdAt: string;
}

export interface Review {
  id: string;
  bookingId: string;
  reviewerUserId: string;
  providerUserId: string;
  rating: number;
  comment: string;
  createdAt: string;
}

export interface JobPost {
  id: string;
  clientUserId: string;
  clientFullName?: string;
  postType: 'seeking_worker' | 'seeking_client';
  title: string;
  category: string;
  municipality: string;
  locationDetails: string;
  description: string;
  budgetMin?: number;
  budgetMax?: number;
  status: 'open' | 'assigned' | 'completed' | 'cancelled';
  offerCount?: number;
  assignedProviderUserId?: string;
  assignedProviderFullName?: string;
  scheduledAt?: string;
  createdAt: string;
  updatedAt: string;
}

export interface JobOffer {
  id: string;
  jobPostId: string;
  providerUserId: string;
  providerFullName?: string;
  message: string;
  proposedPrice?: number;
  media?: Array<{ imageUrl: string; caption?: string }>;
  status: 'pending' | 'accepted' | 'rejected' | 'withdrawn';
  jobTitle?: string;
  jobCategory?: string;
  jobMunicipality?: string;
  createdAt: string;
  updatedAt: string;
}

export interface PublicUserProfile {
  id: string;
  fullName?: string;
  role: 'client' | 'worker' | 'agency' | 'admin';
  status?: string;
}

export interface JobPostPayload {
  postType: 'seeking_worker' | 'seeking_client';
  title: string;
  category: string;
  municipality: string;
  locationDetails?: string;
  description: string;
  budgetMin?: number;
  budgetMax?: number;
  scheduledAt?: string;
}

export interface FeedItem {
  type: 'listing' | 'job' | 'review';
  id: string;
  createdAt: string;
  listing?: {
    id: string;
    providerUserId: string;
    providerRole: string;
    providerDisplayName: string;
    title: string;
    category: string;
    municipality: string;
    description: string;
    priceMin: number;
    priceMax: number;
    estimatedDuration: string;
    requirements: string[];
    availability: string[];
    media: Array<{ imageUrl: string; caption?: string }>;
  };
  job?: {
    id: string;
    clientUserId: string;
    clientFullName?: string;
    title: string;
    category: string;
    municipality: string;
    description: string;
    budgetMin?: number;
    budgetMax?: number;
    status: string;
    offerCount: number;
  };
  review?: {
    id: string;
    providerUserId: string;
    providerName?: string;
    rating: number;
    comment?: string;
  };
}

export interface TimelineEvent {
  type: 'booking' | 'review' | 'job_post' | 'job_offer';
  id: string;
  createdAt: string;
  title: string;
  subtitle: string;
  status?: string;
}

export interface ReportItem {
  id: string;
  reporterUserId: string;
  providerUserId?: string;
  bookingId?: string;
  reason: string;
  details: string;
  status: 'pending' | 'resolved' | 'dismissed';
  createdAt: string;
}

export interface ProviderProfilePayload {
  displayName: string;
  category: string;
  municipality: string;
  services: string[];
  portfolio: Array<{ title: string; imageUrl?: string; description?: string }>;
}

export interface ServiceListingPayload {
  title: string;
  category: string;
  municipality: string;
  description: string;
  priceMin: number;
  priceMax: number;
  estimatedDuration: string;
  requirements: string[];
  availability: string[];
  media: Array<{ imageUrl: string; caption?: string }>;
}

@Injectable({ providedIn: 'root' })
export class MarketplaceApiService {
  private readonly tokenKey = 'hanapgawa_token';
  private readonly userKey = 'hanapgawa_user';

  constructor(
    private readonly http: HttpClient,
    private readonly offline: OfflineStorageService,
  ) {}

  /* ── Auth ──────────────────────────────────────────────────────────── */

  login(payload: { email: string; password: string }): Observable<AuthResponse> {
    return this.http.post<AuthResponse>(`${environment.apiBaseUrl}/auth/login`, payload);
  }

  register(payload: { email: string; password: string; fullName: string }): Observable<RegisterResponse> {
    return this.http.post<RegisterResponse>(`${environment.apiBaseUrl}/auth/register`, payload);
  }

  verifyEmail(payload: { email: string; code: string }): Observable<AuthResponse> {
    return this.http.post<AuthResponse>(`${environment.apiBaseUrl}/auth/email/verify`, payload);
  }

  resendVerificationCode(payload: { email: string }): Observable<ResendVerificationResponse> {
    return this.http.post<ResendVerificationResponse>(`${environment.apiBaseUrl}/auth/email/resend-code`, payload);
  }

  /* ── Providers ─────────────────────────────────────────────────────── */

  searchProviders(filters: { category: string; municipality: string; service: string }): Observable<SearchResponse> {
    let params = new HttpParams();
    if (filters.category.trim()) params = params.set('category', filters.category.trim());
    if (filters.municipality.trim()) params = params.set('municipality', filters.municipality.trim());
    if (filters.service.trim()) params = params.set('service', filters.service.trim());

    return this.http.get<SearchResponse>(`${environment.apiBaseUrl}/providers/search`, { params }).pipe(
      // On success: cache results for offline use
      switchMap(async (res) => {
        await this.offline.cacheProviders(res.profiles);
        return res;
      }),
      // On failure: serve from local SQLite/IndexedDB cache
      catchError(() =>
        from(this.offline.getCachedProviders()).pipe(
          switchMap((cached) => {
            if (cached) {
              return [{ profiles: cached, filters, cache: { source: 'local' as const, hit: true } }];
            }
            return throwError(() => new Error('No network and no local cache available.'));
          }),
        ),
      ),
    ) as Observable<SearchResponse>;
  }

  upsertProviderProfile(payload: ProviderProfilePayload, token: string): Observable<{ profile: ProviderProfile }> {
    return this.http.post<{ profile: ProviderProfile }>(`${environment.apiBaseUrl}/providers`, payload, {
      headers: this.authHeaders(token),
    });
  }

  getProviderDetail(providerUserId: string): Observable<ProviderDetailResponse> {
    return this.http.get<ProviderDetailResponse>(`${environment.apiBaseUrl}/providers/${providerUserId}`);
  }

  getCategories(): Observable<{ categories: Category[] }> {
    return this.http.get<{ categories: Category[] }>(`${environment.apiBaseUrl}/categories`);
  }

  searchServiceListings(filters: { category: string; municipality: string; keyword: string }): Observable<{ listings: ServiceListing[] }> {
    let params = new HttpParams();
    if (filters.category.trim()) params = params.set('category', filters.category.trim());
    if (filters.municipality.trim()) params = params.set('municipality', filters.municipality.trim());
    if (filters.keyword.trim()) params = params.set('keyword', filters.keyword.trim());

    return this.http.get<{ listings: ServiceListing[] }>(`${environment.apiBaseUrl}/services/search`, { params });
  }

  createServiceListing(payload: ServiceListingPayload, token: string): Observable<{ listing: ServiceListing }> {
    return this.http.post<{ listing: ServiceListing }>(`${environment.apiBaseUrl}/services`, payload, {
      headers: this.authHeaders(token),
    });
  }

  /* ── Bookings ──────────────────────────────────────────────────────── */

  createBooking(payload: BookingPayload, token: string): Observable<{ booking: Booking } | { queued: true; queuedBooking: unknown }> {
    return this.http.post<{ booking: Booking }>(`${environment.apiBaseUrl}/bookings`, payload, {
      headers: this.authHeaders(token),
    }).pipe(
      catchError(() =>
        from(this.offline.queueBooking(payload)).pipe(
          switchMap((entry) => [{ queued: true as const, queuedBooking: entry }]),
        ),
      ),
    );
  }

  getMyBookings(token: string): Observable<{ bookings: Booking[] }> {
    return this.http.get<{ bookings: Booking[] }>(`${environment.apiBaseUrl}/bookings`, {
      headers: this.authHeaders(token),
    });
  }

  getBookingDetail(bookingId: string, token: string): Observable<{ booking: Booking }> {
    return this.http.get<{ booking: Booking }>(`${environment.apiBaseUrl}/bookings/${bookingId}`, {
      headers: this.authHeaders(token),
    });
  }

  getAllBookings(token: string): Observable<{ bookings: Booking[] }> {
    return this.http.get<{ bookings: Booking[] }>(`${environment.apiBaseUrl}/admin/bookings`, {
      headers: this.authHeaders(token),
    });
  }

  updateBookingStatus(bookingId: string, status: string, token: string): Observable<{ booking: Booking }> {
    return this.http.patch<{ booking: Booking }>(
      `${environment.apiBaseUrl}/bookings/${bookingId}/status`,
      { status },
      { headers: this.authHeaders(token) },
    );
  }

  startInquiry(payload: { providerUserId: string; serviceListingId?: string; bookingId?: string; initialMessage: string }, token: string): Observable<{ conversation: Conversation; message: ConversationMessage }> {
    return this.http.post<{ conversation: Conversation; message: ConversationMessage }>(`${environment.apiBaseUrl}/inquiries`, payload, {
      headers: this.authHeaders(token),
    });
  }

  getMyConversations(token: string): Observable<{ conversations: Conversation[] }> {
    return this.http.get<{ conversations: Conversation[] }>(`${environment.apiBaseUrl}/inquiries`, {
      headers: this.authHeaders(token),
    });
  }

  getConversationMessages(conversationId: string, token: string): Observable<{ conversation: Conversation; messages: ConversationMessage[] }> {
    return this.http.get<{ conversation: Conversation; messages: ConversationMessage[] }>(`${environment.apiBaseUrl}/inquiries/${conversationId}/messages`, {
      headers: this.authHeaders(token),
    });
  }

  sendConversationMessage(conversationId: string, message: string, token: string): Observable<{ message: ConversationMessage }> {
    return this.http.post<{ message: ConversationMessage }>(`${environment.apiBaseUrl}/inquiries/${conversationId}/messages`, { message }, {
      headers: this.authHeaders(token),
    });
  }

  submitReview(payload: { bookingId: string; rating: number; comment: string }, token: string): Observable<{ review: Review }> {
    return this.http.post<{ review: Review }>(`${environment.apiBaseUrl}/reviews`, payload, {
      headers: this.authHeaders(token),
    });
  }

  submitReport(payload: { providerUserId?: string; bookingId?: string; reason: string; details: string }, token: string): Observable<{ report: ReportItem }> {
    return this.http.post<{ report: ReportItem }>(`${environment.apiBaseUrl}/reports`, payload, {
      headers: this.authHeaders(token),
    });
  }

  /* ── Feed & Timeline ──────────────────────────────────────────────── */

  getFeed(limit = 40): Observable<{ items: FeedItem[] }> {
    return this.http.get<{ items: FeedItem[] }>(`${environment.apiBaseUrl}/feed`, {
      params: new HttpParams().set('limit', limit),
    });
  }

  getTimeline(token: string, limit = 50): Observable<{ events: TimelineEvent[] }> {
    return this.http.get<{ events: TimelineEvent[] }>(`${environment.apiBaseUrl}/feed/timeline`, {
      headers: this.authHeaders(token),
      params: new HttpParams().set('limit', limit),
    });
  }

  /* ── Job posts / offers ────────────────────────────────────────────── */

  createJobPost(payload: JobPostPayload, token: string): Observable<{ jobPost: JobPost }> {
    return this.http.post<{ jobPost: JobPost }>(`${environment.apiBaseUrl}/jobs`, payload, {
      headers: this.authHeaders(token),
    });
  }

  getJobs(token: string, status?: string): Observable<{ jobs: JobPost[] }> {
    let params = new HttpParams();
    if (status) params = params.set('status', status);

    return this.http.get<{ jobs: JobPost[] }>(`${environment.apiBaseUrl}/jobs`, {
      headers: this.authHeaders(token),
      params,
    });
  }

  getJobDetail(jobPostId: string, token: string): Observable<{ jobPost: JobPost; offers: JobOffer[] }> {
    return this.http.get<{ jobPost: JobPost; offers: JobOffer[] }>(`${environment.apiBaseUrl}/jobs/${jobPostId}`, {
      headers: this.authHeaders(token),
    });
  }

  sendJobOffer(jobPostId: string, payload: { message: string; proposedPrice?: number; media?: Array<{ imageUrl: string; caption?: string }> }, token: string): Observable<{ offer: JobOffer }> {
    return this.http.post<{ offer: JobOffer }>(`${environment.apiBaseUrl}/jobs/${jobPostId}/offers`, payload, {
      headers: this.authHeaders(token),
    });
  }

  getPublicUserProfile(userId: string, token: string): Observable<{ user: PublicUserProfile }> {
    return this.http.get<{ user: PublicUserProfile }>(`${environment.apiBaseUrl}/users/${userId}/public`, {
      headers: this.authHeaders(token),
    });
  }

  acceptJobOffer(jobPostId: string, offerId: string, token: string): Observable<{ jobPost: JobPost; offer: JobOffer; booking: Booking }> {
    return this.http.patch<{ jobPost: JobPost; offer: JobOffer; booking: Booking }>(`${environment.apiBaseUrl}/jobs/${jobPostId}/offers/${offerId}/accept`, {}, {
      headers: this.authHeaders(token),
    });
  }

  getMyJobOffers(token: string): Observable<{ offers: JobOffer[] }> {
    return this.http.get<{ offers: JobOffer[] }>(`${environment.apiBaseUrl}/jobs/offers/mine`, {
      headers: this.authHeaders(token),
    });
  }

  getAdminProviders(token: string): Observable<{ providers: SessionUser[] }> {
    return this.http.get<{ providers: SessionUser[] }>(`${environment.apiBaseUrl}/admin/providers`, {
      headers: this.authHeaders(token),
    });
  }

  updateProviderApproval(userId: string, status: 'approved' | 'rejected' | 'pending', token: string): Observable<{ user: SessionUser }> {
    return this.http.patch<{ user: SessionUser }>(`${environment.apiBaseUrl}/admin/providers/${userId}/status`, { status }, {
      headers: this.authHeaders(token),
    });
  }

  getAdminCategories(token: string): Observable<{ categories: Category[] }> {
    return this.http.get<{ categories: Category[] }>(`${environment.apiBaseUrl}/admin/categories`, {
      headers: this.authHeaders(token),
    });
  }

  createCategory(payload: { name: string; description: string; icon: string }, token: string): Observable<{ category: Category }> {
    return this.http.post<{ category: Category }>(`${environment.apiBaseUrl}/admin/categories`, payload, {
      headers: this.authHeaders(token),
    });
  }

  getReports(token: string): Observable<{ reports: ReportItem[] }> {
    return this.http.get<{ reports: ReportItem[] }>(`${environment.apiBaseUrl}/admin/reports`, {
      headers: this.authHeaders(token),
    });
  }

  updateReportStatus(reportId: string, status: 'resolved' | 'dismissed' | 'pending', token: string): Observable<{ report: ReportItem }> {
    return this.http.patch<{ report: ReportItem }>(`${environment.apiBaseUrl}/admin/reports/${reportId}`, { status }, {
      headers: this.authHeaders(token),
    });
  }

  /* ── Offline queue sync ────────────────────────────────────────────── */

  async syncOfflineQueue(token: string): Promise<{ synced: number; failed: number }> {
    const queue = await this.offline.getPendingQueue();
    let synced = 0;
    let failed = 0;

    for (const entry of queue) {
      try {
        await this.http.post(`${environment.apiBaseUrl}/bookings`, entry.payload, {
          headers: this.authHeaders(token),
        }).toPromise();
        await this.offline.removePendingBooking(entry.id);
        synced++;
      } catch {
        failed++;
      }
    }

    return { synced, failed };
  }

  /* ── Session ───────────────────────────────────────────────────────── */

  persistSession(auth: AuthResponse): void {
    localStorage.setItem(this.tokenKey, auth.token);
    localStorage.setItem(this.userKey, JSON.stringify(auth.user));
  }

  clearSession(): void {
    localStorage.removeItem(this.tokenKey);
    localStorage.removeItem(this.userKey);
  }

  getToken(): string {
    return localStorage.getItem(this.tokenKey) || '';
  }

  getStoredUser(): SessionUser | null {
    const raw = localStorage.getItem(this.userKey);
    if (!raw) return null;
    try { return JSON.parse(raw) as SessionUser; } catch { return null; }
  }

  updateStoredUser(user: SessionUser): void {
    localStorage.setItem(this.userKey, JSON.stringify(user));
  }

  private authHeaders(token: string): HttpHeaders {
    return new HttpHeaders({ Authorization: `Bearer ${token}` });
  }
}
