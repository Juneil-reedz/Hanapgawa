import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit } from '@angular/core';

import {
  AuthResponse,
  Booking,
  Category,
  Conversation,
  ConversationMessage,
  MarketplaceApiService,
  ProviderDetailResponse,
  ReportItem,
  ServiceListing,
  SessionUser,
} from '../services/marketplace-api.service';

type HomeView = 'marketplace' | 'orders' | 'inbox' | 'provider' | 'admin';

@Component({
  selector: 'app-home',
  templateUrl: 'home.page.html',
  styleUrls: ['home.page.scss'],
  standalone: false,
})
export class HomePage implements OnInit {
  activeView: HomeView = 'marketplace';
  authMode: 'login' | 'register' = 'login';
  currentUser: SessionUser | null = null;
  token = '';

  loadingAuth = false;
  loadingMarketplace = false;
  loadingBookings = false;
  loadingInbox = false;
  savingProvider = false;
  savingService = false;
  creatingBooking = false;
  creatingInquiry = false;
  sendingMessage = false;
  adminLoading = false;

  authMessage = '';
  marketplaceMessage = '';
  bookingMessage = '';
  inquiryMessage = '';
  providerMessage = '';
  adminMessage = '';

  currentYear = new Date().getFullYear();
  searchCacheSource = '';
  categories: Category[] = [];
  services: ServiceListing[] = [];
  selectedService: ServiceListing | null = null;
  providerDetail: ProviderDetailResponse | null = null;

  bookings: Booking[] = [];
  conversations: Conversation[] = [];
  selectedConversation: Conversation | null = null;
  conversationMessages: ConversationMessage[] = [];
  adminProviders: SessionUser[] = [];
  adminBookings: Booking[] = [];
  adminCategories: Category[] = [];
  adminReports: ReportItem[] = [];

  authForm = {
    fullName: '',
    email: 'client@hanapgawa.demo',
    password: 'Password123!',
    role: 'client' as 'client' | 'worker' | 'agency',
  };

  searchForm = {
    category: '',
    municipality: 'Bongao',
    keyword: '',
  };

  bookingForm = {
    municipality: 'Bongao',
    locationDetails: '',
    notes: '',
    scheduledAt: '',
  };

  inquiryForm = {
    initialMessage: 'Hello, I want to ask about your service availability.',
    replyMessage: '',
  };

  providerProfileForm = {
    displayName: '',
    category: 'Carpentry',
    municipality: 'Bongao',
    servicesText: '',
    portfolioTitle: '',
    portfolioDescription: '',
    portfolioImageUrl: '',
  };

  serviceListingForm = {
    title: '',
    category: 'Carpentry',
    municipality: 'Bongao',
    description: '',
    priceMin: 800,
    priceMax: 2500,
    estimatedDuration: '2 to 5 hours',
    requirementsText: '',
    availabilityText: '',
    mediaUrl: '',
  };

  categoryForm = {
    name: '',
    description: '',
    icon: 'briefcase-outline',
  };

  readonly featuredMunicipalities = ['Bongao', 'Simunul', 'Sitangkai', 'Panglima Sugala'];
  readonly featuredHighlights = [
    'Search approved local services',
    'Book providers with offline queue backup',
    'Track project status like a marketplace order',
  ];

  constructor(private readonly api: MarketplaceApiService) {}

  ngOnInit(): void {
    this.currentUser = this.api.getStoredUser();
    this.token = this.api.getToken();
    this.loadMarketplace();
    this.refreshSessionData();
  }

  switchView(view: HomeView): void {
    this.activeView = view;

    if (view === 'orders') {
      this.loadBookings();
    }

    if (view === 'inbox') {
      this.loadConversations();
    }

    if (view === 'admin') {
      this.loadAdminData();
    }
  }

  switchAuthMode(mode: 'login' | 'register'): void {
    this.authMode = mode;
    this.authMessage = '';
  }

  submitAuth(): void {
    this.loadingAuth = true;
    this.authMessage = '';

    const request = this.authMode === 'login'
      ? this.api.login({ email: this.authForm.email, password: this.authForm.password })
      : this.api.register({
          email: this.authForm.email,
          password: this.authForm.password,
          role: this.authForm.role,
          fullName: this.authForm.fullName,
        });

    request.subscribe({
      next: (response) => this.handleAuthSuccess(response),
      error: (error: HttpErrorResponse) => {
        this.loadingAuth = false;
        this.authMessage = this.extractErrorMessage(error, 'Unable to complete the request right now.');
      },
    });
  }

  logout(): void {
    this.api.clearSession();
    this.currentUser = null;
    this.token = '';
    this.bookings = [];
    this.conversations = [];
    this.selectedConversation = null;
    this.conversationMessages = [];
    this.adminProviders = [];
    this.adminCategories = [];
    this.adminReports = [];
    this.authMessage = 'Signed out.';
    this.activeView = 'marketplace';
  }

  loadMarketplace(): void {
    this.loadingMarketplace = true;
    this.marketplaceMessage = '';

    this.api.getCategories().subscribe({
      next: (response) => {
        this.categories = response.categories;
      },
      error: () => {
        this.categories = [];
      },
    });

    this.api.searchServiceListings(this.searchForm).subscribe({
      next: (response) => {
        this.loadingMarketplace = false;
        this.services = response.listings;
        this.searchCacheSource = 'live';
        this.marketplaceMessage = response.listings.length ? '' : 'No service listings matched your search yet.';
      },
      error: (error: HttpErrorResponse) => {
        this.loadingMarketplace = false;
        this.services = [];
        this.marketplaceMessage = this.extractErrorMessage(error, 'Could not load service listings right now.');
      },
    });
  }

  applyCategory(category: string): void {
    this.searchForm.category = category;
    this.loadMarketplace();
  }

  chooseMunicipality(municipality: string): void {
    this.searchForm.municipality = municipality;
    this.loadMarketplace();
  }

  selectService(service: ServiceListing): void {
    this.selectedService = service;
    this.bookingForm.municipality = service.municipality;
    this.bookingMessage = '';
    this.inquiryMessage = '';
    this.loadProviderDetail(service.providerUserId);
  }

  loadProviderDetail(providerUserId: string): void {
    this.api.getProviderDetail(providerUserId).subscribe({
      next: (response) => {
        this.providerDetail = response;

        if (!this.providerProfileForm.displayName && this.currentUser?.id === providerUserId && response.profile) {
          this.providerProfileForm.displayName = response.profile.displayName;
          this.providerProfileForm.category = response.profile.category;
          this.providerProfileForm.municipality = response.profile.municipality;
          this.providerProfileForm.servicesText = response.profile.services.join(', ');
        }
      },
      error: (error: HttpErrorResponse) => {
        this.marketplaceMessage = this.extractErrorMessage(error, 'Could not load provider details.');
      },
    });
  }

  clearSelectedService(): void {
    this.selectedService = null;
    this.providerDetail = null;
    this.bookingMessage = '';
    this.inquiryMessage = '';
  }

  createBooking(): void {
    if (!this.selectedService || !this.currentUser || !this.token) {
      this.bookingMessage = 'Sign in first to create a booking.';
      return;
    }

    if (!['client', 'admin'].includes(this.currentUser.role)) {
      this.bookingMessage = 'Only client accounts can create bookings.';
      return;
    }

    this.creatingBooking = true;
    this.bookingMessage = '';

    this.api.createBooking({
      providerUserId: this.selectedService.providerUserId,
      serviceListingId: this.selectedService.id,
      serviceCategory: this.selectedService.category,
      municipality: this.bookingForm.municipality,
      locationDetails: this.bookingForm.locationDetails,
      notes: this.bookingForm.notes,
      scheduledAt: this.toIsoDateTime(this.bookingForm.scheduledAt),
    }, this.token).subscribe({
      next: (response) => {
        this.creatingBooking = false;
        this.bookingMessage = 'queued' in response
          ? 'No connection detected. Booking saved in your offline queue.'
          : 'Booking request sent successfully.';
        this.bookingForm.locationDetails = '';
        this.bookingForm.notes = '';
        this.bookingForm.scheduledAt = '';
        this.loadBookings();
      },
      error: (error: HttpErrorResponse) => {
        this.creatingBooking = false;
        this.bookingMessage = this.extractErrorMessage(error, 'Booking failed. Please try again.');
      },
    });
  }

  startInquiry(): void {
    if (!this.selectedService || !this.currentUser || !this.token) {
      this.inquiryMessage = 'Sign in first to start a conversation.';
      return;
    }

    if (!['client', 'admin'].includes(this.currentUser.role)) {
      this.inquiryMessage = 'Only client accounts can start inquiries.';
      return;
    }

    this.creatingInquiry = true;
    this.inquiryMessage = '';

    this.api.startInquiry({
      providerUserId: this.selectedService.providerUserId,
      serviceListingId: this.selectedService.id,
      initialMessage: this.inquiryForm.initialMessage,
    }, this.token).subscribe({
      next: (response) => {
        this.creatingInquiry = false;
        this.inquiryMessage = 'Inquiry sent. Open Inbox to continue the conversation.';
        this.selectedConversation = response.conversation;
        this.conversationMessages = [response.message];
        this.loadConversations();
      },
      error: (error: HttpErrorResponse) => {
        this.creatingInquiry = false;
        this.inquiryMessage = this.extractErrorMessage(error, 'Could not start conversation.');
      },
    });
  }

  submitReportAgainstProvider(): void {
    if (!this.providerDetail || !this.currentUser || !this.token) {
      this.inquiryMessage = 'Sign in before filing a report.';
      return;
    }

    this.api.submitReport({
      providerUserId: this.providerDetail.provider.id,
      reason: 'Service inquiry concern',
      details: 'Client wants admin to review provider communication or service details.',
    }, this.token).subscribe({
      next: () => {
        this.inquiryMessage = 'Report sent to admin for review.';
      },
      error: (error: HttpErrorResponse) => {
        this.inquiryMessage = this.extractErrorMessage(error, 'Could not submit report.');
      },
    });
  }

  loadBookings(): void {
    if (!this.token) {
      return;
    }

    this.loadingBookings = true;
    this.api.getMyBookings(this.token).subscribe({
      next: (response) => {
        this.loadingBookings = false;
        this.bookings = response.bookings;
      },
      error: () => {
        this.loadingBookings = false;
      },
    });
  }

  updateBookingStage(bookingId: string, status: Booking['status']): void {
    if (!this.token) {
      return;
    }

    this.api.updateBookingStatus(bookingId, status, this.token).subscribe({
      next: () => {
        this.loadBookings();

        if (this.currentUser?.role === 'admin') {
          this.loadAdminData();
        }
      },
      error: (error: HttpErrorResponse) => {
        this.bookingMessage = this.extractErrorMessage(error, 'Could not update booking status.');
      },
    });
  }

  loadConversations(): void {
    if (!this.token) {
      return;
    }

    this.loadingInbox = true;
    this.api.getMyConversations(this.token).subscribe({
      next: (response) => {
        this.loadingInbox = false;
        this.conversations = response.conversations;

        if (!this.selectedConversation && response.conversations.length) {
          this.openConversation(response.conversations[0]);
        }
      },
      error: () => {
        this.loadingInbox = false;
      },
    });
  }

  openConversation(conversation: Conversation): void {
    if (!this.token) {
      return;
    }

    this.selectedConversation = conversation;
    this.api.getConversationMessages(conversation.id, this.token).subscribe({
      next: (response) => {
        this.conversationMessages = response.messages;
      },
      error: () => {
        this.conversationMessages = [];
      },
    });
  }

  sendReply(): void {
    if (!this.selectedConversation || !this.token || !this.inquiryForm.replyMessage.trim()) {
      return;
    }

    this.sendingMessage = true;
    this.api.sendConversationMessage(this.selectedConversation.id, this.inquiryForm.replyMessage.trim(), this.token).subscribe({
      next: (response) => {
        this.sendingMessage = false;
        this.conversationMessages = [...this.conversationMessages, response.message];
        this.inquiryForm.replyMessage = '';
        this.loadConversations();
      },
      error: () => {
        this.sendingMessage = false;
      },
    });
  }

  submitProviderProfile(): void {
    if (!this.token) {
      this.providerMessage = 'Sign in before editing your provider profile.';
      return;
    }

    this.savingProvider = true;
    this.providerMessage = '';

    this.api.upsertProviderProfile({
      displayName: this.providerProfileForm.displayName,
      category: this.providerProfileForm.category,
      municipality: this.providerProfileForm.municipality,
      services: this.parseList(this.providerProfileForm.servicesText),
      portfolio: this.providerProfileForm.portfolioTitle
        ? [{
            title: this.providerProfileForm.portfolioTitle,
            description: this.providerProfileForm.portfolioDescription,
            imageUrl: this.providerProfileForm.portfolioImageUrl,
          }]
        : [],
    }, this.token).subscribe({
      next: () => {
        this.savingProvider = false;
        this.providerMessage = 'Provider profile saved.';
        if (this.currentUser) {
          this.loadProviderDetail(this.currentUser.id);
        }
      },
      error: (error: HttpErrorResponse) => {
        this.savingProvider = false;
        this.providerMessage = this.extractErrorMessage(error, 'Could not save provider profile.');
      },
    });
  }

  submitServiceListing(): void {
    if (!this.token) {
      this.providerMessage = 'Sign in before publishing a service.';
      return;
    }

    this.savingService = true;
    this.providerMessage = '';

    this.api.createServiceListing({
      title: this.serviceListingForm.title,
      category: this.serviceListingForm.category,
      municipality: this.serviceListingForm.municipality,
      description: this.serviceListingForm.description,
      priceMin: Number(this.serviceListingForm.priceMin),
      priceMax: Number(this.serviceListingForm.priceMax),
      estimatedDuration: this.serviceListingForm.estimatedDuration,
      requirements: this.parseList(this.serviceListingForm.requirementsText),
      availability: this.parseList(this.serviceListingForm.availabilityText),
      media: this.serviceListingForm.mediaUrl ? [{ imageUrl: this.serviceListingForm.mediaUrl, caption: this.serviceListingForm.title }] : [],
    }, this.token).subscribe({
      next: () => {
        this.savingService = false;
        this.providerMessage = 'Service listing published.';
        this.loadMarketplace();
        if (this.currentUser) {
          this.loadProviderDetail(this.currentUser.id);
        }
      },
      error: (error: HttpErrorResponse) => {
        this.savingService = false;
        this.providerMessage = this.extractErrorMessage(error, 'Could not publish service listing.');
      },
    });
  }

  loadAdminData(): void {
    if (!this.token || this.currentUser?.role !== 'admin') {
      return;
    }

    this.adminLoading = true;

    this.api.getAdminProviders(this.token).subscribe({ next: (response) => { this.adminProviders = response.providers; } });
    this.api.getAllBookings(this.token).subscribe({ next: (response) => { this.adminBookings = response.bookings; } });
    this.api.getAdminCategories(this.token).subscribe({ next: (response) => { this.adminCategories = response.categories; } });
    this.api.getReports(this.token).subscribe({ next: (response) => { this.adminReports = response.reports; this.adminLoading = false; } });
  }

  updateProviderApproval(userId: string, status: 'approved' | 'rejected' | 'pending'): void {
    if (!this.token) {
      return;
    }

    this.api.updateProviderApproval(userId, status, this.token).subscribe({
      next: () => {
        this.adminMessage = 'Provider status updated.';
        this.loadAdminData();
      },
      error: (error: HttpErrorResponse) => {
        this.adminMessage = this.extractErrorMessage(error, 'Could not update provider status.');
      },
    });
  }

  submitCategory(): void {
    if (!this.token) {
      return;
    }

    this.api.createCategory(this.categoryForm, this.token).subscribe({
      next: () => {
        this.categoryForm = { name: '', description: '', icon: 'briefcase-outline' };
        this.adminMessage = 'Category created.';
        this.loadAdminData();
        this.loadMarketplace();
      },
      error: (error: HttpErrorResponse) => {
        this.adminMessage = this.extractErrorMessage(error, 'Could not create category.');
      },
    });
  }

  resolveReport(reportId: string, status: 'resolved' | 'dismissed'): void {
    if (!this.token) {
      return;
    }

    this.api.updateReportStatus(reportId, status, this.token).subscribe({
      next: () => {
        this.adminMessage = 'Report updated.';
        this.loadAdminData();
      },
      error: (error: HttpErrorResponse) => {
        this.adminMessage = this.extractErrorMessage(error, 'Could not update report.');
      },
    });
  }

  bookingActions(booking: Booking): Array<{ label: string; status: Booking['status'] }> {
    if (!this.currentUser) {
      return [];
    }

    if (this.currentUser.role === 'client') {
      if (booking.status === 'completion_requested') {
        return [{ label: 'Confirm Complete', status: 'completed' }];
      }

      if (['pending', 'accepted', 'in_progress'].includes(booking.status)) {
        return [{ label: 'Request Cancellation', status: 'cancellation_requested' }];
      }
    }

    if (['worker', 'agency'].includes(this.currentUser.role)) {
      if (booking.status === 'pending') {
        return [
          { label: 'Accept', status: 'accepted' },
          { label: 'Reject', status: 'rejected' },
        ];
      }

      if (booking.status === 'accepted') {
        return [
          { label: 'Start Work', status: 'in_progress' },
          { label: 'Request Cancellation', status: 'cancellation_requested' },
        ];
      }

      if (booking.status === 'in_progress') {
        return [{ label: 'Mark Complete', status: 'completion_requested' }];
      }

      if (booking.status === 'cancellation_requested') {
        return [{ label: 'Finalize Cancel', status: 'cancelled' }];
      }
    }

    if (this.currentUser.role === 'admin' && booking.status === 'cancellation_requested') {
      return [{ label: 'Finalize Cancel', status: 'cancelled' }];
    }

    return [];
  }

  trackById(_index: number, item: { id: string }): string {
    return item.id;
  }

  isProviderRole(): boolean {
    return ['worker', 'agency', 'admin'].includes(this.currentUser?.role || '');
  }

  isAdmin(): boolean {
    return this.currentUser?.role === 'admin';
  }

  private refreshSessionData(): void {
    if (!this.currentUser || !this.token) {
      return;
    }

    this.loadBookings();
    this.loadConversations();

    if (this.isAdmin()) {
      this.loadAdminData();
    }

    if (this.isProviderRole()) {
      this.loadProviderDetail(this.currentUser.id);
    }
  }

  private handleAuthSuccess(response: AuthResponse): void {
    this.api.persistSession(response);
    this.currentUser = response.user;
    this.token = response.token;
    this.loadingAuth = false;
    this.authMessage = this.authMode === 'login'
      ? `Welcome back, ${response.user.fullName || response.user.email}.`
      : 'Account created. Provider accounts may still need admin approval before appearing in search.';
    this.refreshSessionData();
  }

  private parseList(value: string): string[] {
    return value
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean);
  }

  private toIsoDateTime(value: string): string | undefined {
    return value ? new Date(value).toISOString() : undefined;
  }

  private extractErrorMessage(error: HttpErrorResponse, fallback: string): string {
    return error.error?.error?.message || fallback;
  }
}
