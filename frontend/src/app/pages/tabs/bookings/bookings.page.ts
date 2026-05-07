import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, ViewChild } from '@angular/core';
import { Router } from '@angular/router';
import { IonContent } from '@ionic/angular';

import { Booking, Conversation, ConversationMessage, MarketplaceApiService, Review } from '../../../services/marketplace-api.service';

interface BookingPartner {
  userId: string;
  name: string;
  role: string;
  category: string;
}

@Component({
  selector: 'app-bookings',
  templateUrl: 'bookings.page.html',
  styleUrls: ['bookings.page.scss'],
  standalone: false,
})
export class BookingsPage implements OnInit {
  @ViewChild('chatContent') chatContent?: IonContent;

  activeSegment: 'orders' | 'inbox' = 'orders';

  // Orders
  bookings: Booking[] = [];
  loading = false;
  errorMessage = '';

  // Inbox — list
  conversations: Conversation[] = [];
  loadingInbox = false;
  inboxMessage = '';

  // Inbox — chat modal
  openChat: Conversation | null = null;
  messages: ConversationMessage[] = [];
  loadingMessages = false;
  replyDraft = '';
  sendingReply = false;
  sendError = '';

  // Compose modal (clients only)
  showCompose = false;
  composePartner: BookingPartner | null = null;
  composeDraft = '';
  bookingPartners: BookingPartner[] = [];
  loadingPartners = false;
  sendingCompose = false;
  composeError = '';

  // Review state
  reviewingBooking: Booking | null = null;
  reviewForm = { rating: 0, comment: '' };
  submittingReview = false;
  reviewMessage = '';
  reviewSuccess = false;
  reviewedBookingIds = new Set<string>();
  stars = [1, 2, 3, 4, 5];

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

  constructor(private readonly api: MarketplaceApiService, private readonly router: Router) {}

  get currentUser() {
    return this.api.getStoredUser();
  }

  get token(): string {
    return this.api.getToken();
  }

  get isClient(): boolean {
    return this.currentUser?.role === 'client';
  }

  ngOnInit(): void {
    this.loadBookings();
    this.loadConversations();
  }

  // ── Orders ──────────────────────────────────────────────────────────

  loadBookings(): void {
    this.loading = true;
    this.errorMessage = '';

    this.api.getMyBookings(this.token).subscribe({
      next: (res) => {
        this.loading = false;
        this.bookings = res.bookings.sort(
          (a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
        );
      },
      error: (err: HttpErrorResponse) => {
        this.loading = false;
        this.errorMessage = err.error?.error?.message || 'Could not load bookings.';
      },
    });
  }

  updateStatus(booking: Booking, status: Booking['status']): void {
    this.api.updateBookingStatus(booking.id, status, this.token).subscribe({
      next: () => this.loadBookings(),
      error: (err: HttpErrorResponse) => {
        this.errorMessage = err.error?.error?.message || 'Could not update booking.';
      },
    });
  }

  openBookingDetail(booking: Booking): void {
    this.router.navigate(['/tabs/bookings', booking.id]);
  }

  getActions(booking: Booking): Array<{ label: string; status: Booking['status'] }> {
    const role = this.currentUser?.role;

    if (role === 'client') {
      if (booking.status === 'completion_requested') return [{ label: 'Confirm Complete', status: 'completed' }];
      if (['pending', 'accepted', 'in_progress'].includes(booking.status)) return [{ label: 'Request Cancel', status: 'cancellation_requested' }];
    }

    if (role === 'worker' || role === 'agency') {
      if (booking.status === 'pending') return [{ label: 'Accept', status: 'accepted' }, { label: 'Reject', status: 'rejected' }];
      if (booking.status === 'accepted') return [{ label: 'Start', status: 'in_progress' }];
      if (booking.status === 'in_progress') return [{ label: 'Mark Complete', status: 'completion_requested' }];
    }

    return booking.status === 'cancellation_requested' ? [{ label: 'Finalize Cancel', status: 'cancelled' }] : [];
  }

  // ── Inbox — list ────────────────────────────────────────────────────

  loadConversations(): void {
    this.loadingInbox = true;
    this.inboxMessage = '';

    this.api.getMyConversations(this.token).subscribe({
      next: (res) => {
        this.loadingInbox = false;
        this.conversations = res.conversations;
        if (!res.conversations.length) {
          this.inboxMessage = this.isClient
            ? 'No messages yet. Contact a provider from Discover to start chatting.'
            : 'No messages yet. Clients will contact you after viewing your listings.';
        }
      },
      error: (err: HttpErrorResponse) => {
        this.loadingInbox = false;
        this.inboxMessage = err.error?.error?.message || 'Could not load conversations.';
      },
    });
  }

  otherPartyName(conv: Conversation): string {
    const me = this.currentUser?.id;
    if (conv.clientUserId === me) return conv.providerName || 'Provider';
    return conv.clientName || 'Client';
  }

  otherPartyInitials(conv: Conversation): string {
    return this.otherPartyName(conv).slice(0, 2).toUpperCase();
  }

  timeAgo(value: string): string {
    const diff = Date.now() - new Date(value).getTime();
    const mins = Math.floor(diff / 60000);
    if (mins < 1) return 'just now';
    if (mins < 60) return `${mins}m`;
    const hrs = Math.floor(mins / 60);
    if (hrs < 24) return `${hrs}h`;
    return new Date(value).toLocaleDateString('en-PH', { month: 'short', day: 'numeric' });
  }

  // ── Inbox — chat ─────────────────────────────────────────────────────

  openConversation(conv: Conversation): void {
    this.openChat = conv;
    this.messages = [];
    this.replyDraft = '';
    this.sendError = '';
    this.loadingMessages = true;

    this.api.getConversationMessages(conv.id, this.token).subscribe({
      next: (res) => {
        this.loadingMessages = false;
        this.messages = res.messages;
        this.scrollToBottom();
      },
      error: () => {
        this.loadingMessages = false;
        this.messages = [];
      },
    });
  }

  closeChat(): void {
    this.openChat = null;
    this.messages = [];
    this.replyDraft = '';
    this.sendError = '';
  }

  sendReply(): void {
    if (!this.openChat || !this.replyDraft.trim()) return;

    this.sendingReply = true;
    this.sendError = '';
    const text = this.replyDraft.trim();

    this.api.sendConversationMessage(this.openChat.id, text, this.token).subscribe({
      next: (res) => {
        this.sendingReply = false;
        this.replyDraft = '';
        this.messages = [...this.messages, res.message];

        // Update preview in list
        const idx = this.conversations.findIndex(c => c.id === this.openChat?.id);
        if (idx !== -1) {
          this.conversations[idx] = { ...this.conversations[idx], lastMessagePreview: text, updatedAt: new Date().toISOString() };
        }

        this.scrollToBottom();
      },
      error: (err: HttpErrorResponse) => {
        this.sendingReply = false;
        this.sendError = err.error?.error?.message || 'Could not send message.';
      },
    });
  }

  onReplyKeydown(event: KeyboardEvent): void {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      this.sendReply();
    }
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      this.chatContent?.scrollToBottom(200);
    }, 80);
  }

  // ── Compose — new conversation (clients only) ───────────────────────

  openCompose(): void {
    this.showCompose = true;
    this.composePartner = null;
    this.composeDraft = '';
    this.composeError = '';
    this.bookingPartners = [];
    this.loadingPartners = true;

    this.api.getMyBookings(this.token).subscribe({
      next: (res) => {
        this.loadingPartners = false;
        const seen = new Set<string>();
        const partners: BookingPartner[] = [];

        for (const b of res.bookings) {
          const pid = b.providerUserId;
          if (!seen.has(pid)) {
            seen.add(pid);
            partners.push({
              userId: pid,
              name: 'Provider', // resolved below via existing conversations
              role: 'worker',
              category: b.serviceCategory,
            });
          }
        }

        // Enrich names from existing conversations
        for (const p of partners) {
          const conv = this.conversations.find(
            c => c.providerUserId === p.userId || c.clientUserId === p.userId,
          );
          if (conv) {
            p.name = conv.providerUserId === p.userId
              ? (conv.providerName || 'Provider')
              : (conv.clientName || 'Client');
          }
        }

        this.bookingPartners = partners;
      },
      error: () => {
        this.loadingPartners = false;
        this.composeError = 'Could not load contacts.';
      },
    });
  }

  closeCompose(): void {
    this.showCompose = false;
    this.composePartner = null;
    this.composeDraft = '';
    this.composeError = '';
  }

  selectPartner(partner: BookingPartner): void {
    this.composePartner = partner;
  }

  sendNewMessage(): void {
    if (!this.composePartner || !this.composeDraft.trim()) return;

    this.sendingCompose = true;
    this.composeError = '';

    this.api.startInquiry({
      providerUserId: this.composePartner.userId,
      initialMessage: this.composeDraft.trim(),
    }, this.token).subscribe({
      next: (res) => {
        this.sendingCompose = false;
        this.closeCompose();
        this.conversations = [res.conversation, ...this.conversations];
        this.inboxMessage = '';
        this.openConversation(res.conversation);
      },
      error: (err: HttpErrorResponse) => {
        this.sendingCompose = false;
        this.composeError = err.error?.error?.message || 'Could not send message.';
      },
    });
  }

  partnerInitials(p: BookingPartner): string {
    return p.name.slice(0, 2).toUpperCase();
  }

  // ── Review ──────────────────────────────────────────────────────────

  canReview(booking: Booking): boolean {
    return this.currentUser?.role === 'client' && booking.status === 'completed' && !this.reviewedBookingIds.has(booking.id);
  }

  openReview(booking: Booking): void {
    this.reviewingBooking = booking;
    this.reviewForm = { rating: 0, comment: '' };
    this.reviewMessage = '';
    this.reviewSuccess = false;
  }

  closeReview(): void {
    this.reviewingBooking = null;
    this.reviewMessage = '';
    this.reviewSuccess = false;
  }

  setRating(star: number): void {
    this.reviewForm.rating = star;
  }

  submitReview(): void {
    if (!this.reviewingBooking || this.reviewForm.rating === 0) {
      this.reviewMessage = 'Please select a star rating.';
      return;
    }

    this.submittingReview = true;
    this.reviewMessage = '';

    this.api.submitReview({ bookingId: this.reviewingBooking.id, rating: this.reviewForm.rating, comment: this.reviewForm.comment }, this.token).subscribe({
      next: (res: { review: Review }) => {
        this.submittingReview = false;
        this.reviewSuccess = true;
        this.reviewMessage = 'Review submitted! Thank you for your feedback.';
        this.reviewedBookingIds.add(res.review.bookingId);
        setTimeout(() => this.closeReview(), 1800);
      },
      error: (err) => {
        this.submittingReview = false;
        this.reviewSuccess = false;
        this.reviewMessage = err.error?.error?.message || 'Could not submit review.';
      },
    });
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  formatDate(value: string): string {
    return new Date(value).toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' });
  }

  formatSchedule(value?: string): string {
    if (!value) return 'No schedule set';
    return new Date(value).toLocaleString('en-PH', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
  }

  formatTime(value: string): string {
    return new Date(value).toLocaleTimeString('en-PH', { hour: '2-digit', minute: '2-digit' });
  }

  trackBooking(_i: number, b: Booking): string { return b.id; }
  trackConversation(_i: number, c: Conversation): string { return c.id; }
  trackMessage(_i: number, m: ConversationMessage): string { return m.id; }
  trackPartner(_i: number, p: BookingPartner): string { return p.userId; }
}
