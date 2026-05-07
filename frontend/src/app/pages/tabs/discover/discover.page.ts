import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';

import { FeedItem, MarketplaceApiService, ProviderDetailResponse, ServiceListing } from '../../../services/marketplace-api.service';

@Component({
  selector: 'app-discover',
  templateUrl: 'discover.page.html',
  styleUrls: ['discover.page.scss'],
  standalone: false,
})
export class DiscoverPage implements OnInit {
  activeSegment: 'feed' | 'browse' = 'feed';

  // Feed
  feedItems: FeedItem[] = [];
  loadingFeed = false;
  feedMessage = '';

  // Browse
  listings: ServiceListing[] = [];
  loadingServices = false;
  searchMessage = '';

  // Booking modal
  selectedService: ServiceListing | null = null;
  providerDetail: ProviderDetailResponse | null = null;
  creatingBooking = false;
  creatingInquiry = false;
  bookingMessage = '';
  inquiryMessage = '';

  quickCategories = ['Carpentry', 'Electrical', 'Plumbing', 'Home Services', 'Tutoring', 'Beauty'];
  municipalities = ['Bongao', 'Simunul', 'Sitangkai', 'Panglima Sugala', 'Turtle Islands'];

  searchForm = { category: '', municipality: '', keyword: '' };
  bookingForm = { municipality: '', locationDetails: '', notes: '', scheduledAt: '' };
  inquiryDraft = 'Hello, I want to ask more about this service.';

  get token(): string {
    return this.api.getToken();
  }

  get currentUser() {
    return this.api.getStoredUser();
  }

  constructor(
    private readonly api: MarketplaceApiService,
    private readonly route: ActivatedRoute,
    private readonly router: Router,
  ) {}

  ngOnInit(): void {
    const keyword = this.route.snapshot.queryParamMap.get('keyword');
    if (keyword) {
      this.searchForm.keyword = keyword;
      this.activeSegment = 'browse';
    }

    this.loadFeed();
    if (this.activeSegment === 'browse') {
      this.search();
    }
  }

  onSegmentChange(): void {
    if (this.activeSegment === 'browse' && !this.listings.length) {
      this.search();
    }
  }

  // ── Feed ────────────────────────────────────────────────────────────

  loadFeed(): void {
    this.loadingFeed = true;
    this.feedMessage = '';

    this.api.getFeed(40).subscribe({
      next: (res) => {
        this.loadingFeed = false;
        this.feedItems = res.items;
        if (!res.items.length) {
          this.feedMessage = 'No activity yet. Be the first to post a service or job!';
        }
      },
      error: (err: HttpErrorResponse) => {
        this.loadingFeed = false;
        this.feedMessage = err.error?.error?.message || 'Could not load feed right now.';
      },
    });
  }

  feedItemFromListing(item: FeedItem): void {
    if (!item.listing) return;
    const sl = item.listing as unknown as ServiceListing;
    sl.id = item.listing.id;
    this.openBooking(sl);
  }

  openFeedListing(item: FeedItem): void {
    if (!item.listing) return;
    this.router.navigate(['/tabs/discover/provider', item.listing.providerUserId]);
  }

  openFeedJob(item: FeedItem): void {
    this.router.navigate(['/tabs/jobs']);
  }

  openFeedProvider(item: FeedItem): void {
    const id = item.listing?.providerUserId || item.review?.providerUserId;
    if (id) this.router.navigate(['/tabs/discover/provider', id]);
  }

  stars(n: number): string[] {
    return Array.from({ length: 5 }, (_, i) => (i < n ? 'star' : 'star-outline'));
  }

  timeAgo(value: string): string {
    const diff = Date.now() - new Date(value).getTime();
    const mins = Math.floor(diff / 60000);
    if (mins < 1) return 'just now';
    if (mins < 60) return `${mins}m ago`;
    const hrs = Math.floor(mins / 60);
    if (hrs < 24) return `${hrs}h ago`;
    const days = Math.floor(hrs / 24);
    if (days < 7) return `${days}d ago`;
    return new Date(value).toLocaleDateString('en-PH', { month: 'short', day: 'numeric' });
  }

  trackFeed(_i: number, item: FeedItem): string {
    return `${item.type}-${item.id}`;
  }

  // ── Browse ───────────────────────────────────────────────────────────

  search(): void {
    this.loadingServices = true;
    this.searchMessage = '';

    this.api.searchServiceListings(this.searchForm).subscribe({
      next: (res) => {
        this.loadingServices = false;
        this.listings = res.listings;
        if (!res.listings.length) {
          this.searchMessage = 'No approved service listings matched your filters.';
        }
      },
      error: (err: HttpErrorResponse) => {
        this.loadingServices = false;
        this.searchMessage = err.error?.error?.message || 'Could not load services right now.';
      },
    });
  }

  applyCategory(category: string): void {
    this.searchForm.category = this.searchForm.category === category ? '' : category;
    this.search();
  }

  applyMunicipality(municipality: string): void {
    this.searchForm.municipality = this.searchForm.municipality === municipality ? '' : municipality;
    this.search();
  }

  clearFilters(): void {
    this.searchForm = { category: '', municipality: '', keyword: '' };
    this.search();
  }

  openProvider(service: ServiceListing): void {
    this.router.navigate(['/tabs/discover/provider', service.providerUserId]);
  }

  openBooking(service: ServiceListing): void {
    this.selectedService = service;
    this.providerDetail = null;
    this.bookingMessage = '';
    this.inquiryMessage = '';
    this.bookingForm.municipality = service.municipality;
    this.bookingForm.locationDetails = '';
    this.bookingForm.notes = '';
    this.bookingForm.scheduledAt = '';
    this.api.getProviderDetail(service.providerUserId).subscribe({
      next: (res) => { this.providerDetail = res; },
    });
  }

  closeBooking(): void {
    this.selectedService = null;
    this.providerDetail = null;
    this.bookingMessage = '';
    this.inquiryMessage = '';
  }

  submitBooking(): void {
    if (!this.selectedService) return;

    this.creatingBooking = true;
    this.bookingMessage = '';

    this.api.createBooking(
      {
        providerUserId: this.selectedService.providerUserId,
        serviceListingId: this.selectedService.id,
        serviceCategory: this.selectedService.category,
        municipality: this.bookingForm.municipality,
        locationDetails: this.bookingForm.locationDetails,
        notes: this.bookingForm.notes,
        scheduledAt: this.bookingForm.scheduledAt ? new Date(this.bookingForm.scheduledAt).toISOString() : undefined,
      },
      this.token,
    ).subscribe({
      next: (res) => {
        this.creatingBooking = false;
        this.bookingMessage =
          'queued' in res
            ? 'No internet detected. Booking saved offline and will sync later.'
            : 'Booking request sent successfully.';
      },
      error: (err: HttpErrorResponse) => {
        this.creatingBooking = false;
        this.bookingMessage = err.error?.error?.message || 'Booking failed. Please try again.';
      },
    });
  }

  contactProvider(): void {
    if (!this.selectedService) return;

    this.creatingInquiry = true;
    this.inquiryMessage = '';

    this.api.startInquiry(
      {
        providerUserId: this.selectedService.providerUserId,
        serviceListingId: this.selectedService.id,
        initialMessage: this.inquiryDraft,
      },
      this.token,
    ).subscribe({
      next: () => {
        this.creatingInquiry = false;
        this.inquiryMessage = 'Inquiry sent. Open the Bookings tab inbox to continue chatting.';
      },
      error: (err: HttpErrorResponse) => {
        this.creatingInquiry = false;
        this.inquiryMessage = err.error?.error?.message || 'Could not start inquiry.';
      },
    });
  }

  reportProvider(): void {
    if (!this.providerDetail) return;

    this.api.submitReport(
      {
        providerUserId: this.providerDetail.provider.id,
        reason: 'Provider concern',
        details: 'Client submitted a provider concern from the marketplace screen.',
      },
      this.token,
    ).subscribe({
      next: () => { this.inquiryMessage = 'Report sent to admin.'; },
      error: (err: HttpErrorResponse) => {
        this.inquiryMessage = err.error?.error?.message || 'Could not send report.';
      },
    });
  }

  trackListing(_i: number, listing: ServiceListing): string {
    return listing.id;
  }
}
