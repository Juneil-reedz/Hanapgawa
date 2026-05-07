import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit } from '@angular/core';
import { ActivatedRoute } from '@angular/router';

import { Booking, MarketplaceApiService } from '../../../services/marketplace-api.service';

@Component({
  selector: 'app-booking-detail',
  templateUrl: 'booking-detail.page.html',
  styleUrls: ['booking-detail.page.scss'],
  standalone: false,
})
export class BookingDetailPage implements OnInit {
  booking: Booking | null = null;
  loading = false;
  message = '';

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

  constructor(private readonly api: MarketplaceApiService, private readonly route: ActivatedRoute) {}

  get token(): string {
    return this.api.getToken();
  }

  get currentUser() {
    return this.api.getStoredUser();
  }

  ngOnInit(): void {
    this.loadBooking();
  }

  loadBooking(): void {
    const bookingId = this.route.snapshot.paramMap.get('bookingId');
    if (!bookingId) {
      this.message = 'Booking not found.';
      return;
    }

    this.loading = true;
    this.message = '';

    this.api.getBookingDetail(bookingId, this.token).subscribe({
      next: (res) => {
        this.loading = false;
        this.booking = res.booking;
      },
      error: (err: HttpErrorResponse) => {
        this.loading = false;
        this.message = err.error?.error?.message || 'Could not load booking details.';
      },
    });
  }

  updateStatus(status: Booking['status']): void {
    if (!this.booking) return;

    this.api.updateBookingStatus(this.booking.id, status, this.token).subscribe({
      next: (res) => {
        this.booking = res.booking;
      },
      error: (err: HttpErrorResponse) => {
        this.message = err.error?.error?.message || 'Could not update booking.';
      },
    });
  }

  getActions(): Array<{ label: string; status: Booking['status'] }> {
    if (!this.booking) return [];
    const role = this.currentUser?.role;

    if (role === 'client') {
      if (this.booking.status === 'completion_requested') return [{ label: 'Confirm Complete', status: 'completed' }];
      if (['pending', 'accepted', 'in_progress'].includes(this.booking.status)) return [{ label: 'Request Cancel', status: 'cancellation_requested' }];
    }

    if (role === 'worker' || role === 'agency') {
      if (this.booking.status === 'pending') return [{ label: 'Accept', status: 'accepted' }, { label: 'Reject', status: 'rejected' }];
      if (this.booking.status === 'accepted') return [{ label: 'Start', status: 'in_progress' }];
      if (this.booking.status === 'in_progress') return [{ label: 'Mark Complete', status: 'completion_requested' }];
    }

    return this.booking.status === 'cancellation_requested' ? [{ label: 'Finalize Cancel', status: 'cancelled' }] : [];
  }

  formatDate(value?: string): string {
    if (!value) return 'Not set';
    return new Date(value).toLocaleString('en-PH', { month: 'short', day: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit' });
  }
}
