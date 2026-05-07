import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit } from '@angular/core';

import {
  Booking,
  Category,
  MarketplaceApiService,
  ProviderProfilePayload,
  ReportItem,
  ServiceListingPayload,
  SessionUser,
} from '../../../services/marketplace-api.service';
import { OfflineStorageService, QueuedBooking } from '../../../services/offline-storage.service';

@Component({
  selector: 'app-dashboard',
  templateUrl: 'dashboard.page.html',
  styleUrls: ['dashboard.page.scss'],
  standalone: false,
})
export class DashboardPage implements OnInit {
  user: SessionUser | null = null;
  bookings: Booking[] = [];
  pendingQueue: QueuedBooking[] = [];
  loadingBookings = false;
  bookingError = '';
  actionMessage = '';
  actionSuccess = false;
  syncing = false;
  syncResult = '';

  activeSegment: 'incoming' | 'profile' | 'services' | 'admin' | 'queue' = 'incoming';

  profileForm: ProviderProfilePayload = {
    displayName: '',
    category: '',
    municipality: '',
    services: [],
    portfolio: [],
  };
  servicesInput = '';
  savingProfile = false;
  profileMessage = '';
  profileSuccess = false;

  serviceForm: ServiceListingPayload = {
    title: '',
    category: 'Carpentry',
    municipality: 'Bongao',
    description: '',
    priceMin: 800,
    priceMax: 2500,
    estimatedDuration: '2 to 5 hours',
    requirements: [],
    availability: [],
    media: [],
  };
  requirementsInput = '';
  availabilityInput = '';
  mediaUrl = '';
  serviceMediaPreview = '';
  savingService = false;

  adminProviders: SessionUser[] = [];
  adminReports: ReportItem[] = [];
  adminCategories: Category[] = [];
  categoryForm = { name: '', description: '', icon: 'briefcase-outline' };
  adminMessage = '';

  statusColors: Record<string, string> = {
      pending: 'warning',
      accepted: 'primary',
      in_progress: 'tertiary',
      completion_requested: 'secondary',
      completed: 'success',
      rejected: 'danger',
      cancellation_requested: 'warning',
      cancelled: 'medium',
    };

  municipalities = ['Bongao', 'Simunul', 'Sitangkai', 'Panglima Sugala', 'Turtle Islands'];

  get token(): string { return this.api.getToken(); }

  get incomingBookings(): Booking[] {
    if (this.user?.role === 'admin') {
      return this.bookings;
    }

    return this.bookings.filter(b => b.providerUserId === this.user?.id);
  }

  get isAdmin(): boolean {
    return this.user?.role === 'admin';
  }

  get stats() {
    const incoming = this.incomingBookings;
    return {
      total: incoming.length,
      pending: incoming.filter(b => b.status === 'pending').length,
      accepted: incoming.filter(b => b.status === 'accepted').length,
      completed: incoming.filter(b => b.status === 'completed').length,
    };
  }

  constructor(
    private readonly api: MarketplaceApiService,
    private readonly offline: OfflineStorageService,
  ) {}

  ngOnInit(): void {
    this.user = this.api.getStoredUser();
    this.loadBookings();
    this.loadQueue();
    if (this.isAdmin) {
      this.loadAdminData();
    }
  }

  loadBookings(): void {
    this.loadingBookings = true;
    this.bookingError = '';

    this.api.getMyBookings(this.token).subscribe({
      next: (res) => {
        this.loadingBookings = false;
        this.bookings = res.bookings;
      },
      error: (err: HttpErrorResponse) => {
        this.loadingBookings = false;
        this.bookingError = err.error?.error?.message || 'Could not load bookings.';
      },
    });
  }

  async loadQueue(): Promise<void> {
    this.pendingQueue = await this.offline.getPendingQueue();
  }

  updateStatus(booking: Booking, status: Booking['status']): void {
    this.actionMessage = '';

    this.api.updateBookingStatus(booking.id, status, this.token).subscribe({
      next: (res) => {
        const idx = this.bookings.findIndex(b => b.id === booking.id);
        if (idx !== -1) this.bookings[idx] = res.booking;
        this.actionSuccess = true;
        this.actionMessage = `Booking marked as ${status}.`;
      },
      error: (err: HttpErrorResponse) => {
        this.actionSuccess = false;
        this.actionMessage = err.error?.error?.message || 'Action failed.';
      },
    });
  }

  bookingActions(booking: Booking): Array<{ label: string; status: Booking['status'] }> {
    if (booking.status === 'pending') {
      return [
        { label: 'Accept', status: 'accepted' },
        { label: 'Reject', status: 'rejected' },
      ];
    }

    if (booking.status === 'accepted') {
      return [{ label: 'Start Work', status: 'in_progress' }];
    }

    if (booking.status === 'in_progress') {
      return [{ label: 'Request Completion', status: 'completion_requested' }];
    }

    if (booking.status === 'cancellation_requested') {
      return [{ label: 'Finalize Cancel', status: 'cancelled' }];
    }

    return [];
  }

  saveProfile(): void {
    this.savingProfile = true;
    this.profileMessage = '';

    this.profileForm.services = this.servicesInput
      .split(',')
      .map(s => s.trim())
      .filter(s => s.length > 0);

    this.api.upsertProviderProfile(this.profileForm, this.token).subscribe({
      next: () => {
        this.savingProfile = false;
        this.profileSuccess = true;
        this.profileMessage = 'Provider profile saved successfully.';
      },
      error: (err: HttpErrorResponse) => {
        this.savingProfile = false;
        this.profileSuccess = false;
        this.profileMessage = err.error?.error?.message || 'Could not save profile.';
      },
    });
  }

  saveService(): void {
    this.savingService = true;
    this.serviceForm.requirements = this.requirementsInput.split(',').map(s => s.trim()).filter(Boolean);
    this.serviceForm.availability = this.availabilityInput.split(',').map(s => s.trim()).filter(Boolean);
    const imageUrl = this.serviceMediaPreview || this.mediaUrl;
    this.serviceForm.media = imageUrl ? [{ imageUrl, caption: this.serviceForm.title }] : [];

    this.api.createServiceListing(this.serviceForm, this.token).subscribe({
      next: () => {
        this.savingService = false;
        this.profileSuccess = true;
        this.profileMessage = 'Service listing published successfully.';
        this.serviceMediaPreview = '';
        this.mediaUrl = '';
      },
      error: (err: HttpErrorResponse) => {
        this.savingService = false;
        this.profileSuccess = false;
        this.profileMessage = err.error?.error?.message || 'Could not publish service listing.';
      },
    });
  }

  onServicePhotoSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = () => {
      this.serviceMediaPreview = String(reader.result);
    };
    reader.readAsDataURL(file);
    input.value = '';
  }

  removeServicePhoto(): void {
    this.serviceMediaPreview = '';
  }

  async syncQueue(): Promise<void> {
    this.syncing = true;
    this.syncResult = '';
    const result = await this.api.syncOfflineQueue(this.token);
    this.syncing = false;
    this.syncResult = `Synced ${result.synced} booking(s). ${result.failed} failed.`;
    await this.loadQueue();
    if (result.synced > 0) this.loadBookings();
  }

  async removeFromQueue(id: string): Promise<void> {
    await this.offline.removePendingBooking(id);
    await this.loadQueue();
  }

  formatDate(value: string): string {
    return new Date(value).toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' });
  }

  trackBooking(_i: number, b: Booking): string { return b.id; }
  trackQueued(_i: number, q: QueuedBooking): string { return q.id; }

  loadAdminData(): void {
    this.api.getAdminProviders(this.token).subscribe({ next: (res) => { this.adminProviders = res.providers; } });
    this.api.getReports(this.token).subscribe({ next: (res) => { this.adminReports = res.reports; } });
    this.api.getAdminCategories(this.token).subscribe({ next: (res) => { this.adminCategories = res.categories; } });
  }

  updateProviderApproval(userId: string, status: 'approved' | 'rejected' | 'pending'): void {
    this.api.updateProviderApproval(userId, status, this.token).subscribe({
      next: () => {
        this.adminMessage = 'Provider approval updated.';
        this.loadAdminData();
      },
      error: (err: HttpErrorResponse) => {
        this.adminMessage = err.error?.error?.message || 'Could not update provider.';
      },
    });
  }

  createCategory(): void {
    this.api.createCategory(this.categoryForm, this.token).subscribe({
      next: () => {
        this.adminMessage = 'Category added.';
        this.categoryForm = { name: '', description: '', icon: 'briefcase-outline' };
        this.loadAdminData();
      },
      error: (err: HttpErrorResponse) => {
        this.adminMessage = err.error?.error?.message || 'Could not add category.';
      },
    });
  }

  resolveReport(reportId: string, status: 'resolved' | 'dismissed'): void {
    this.api.updateReportStatus(reportId, status, this.token).subscribe({
      next: () => {
        this.adminMessage = 'Report updated.';
        this.loadAdminData();
      },
      error: (err: HttpErrorResponse) => {
        this.adminMessage = err.error?.error?.message || 'Could not update report.';
      },
    });
  }
}
