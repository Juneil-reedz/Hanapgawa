import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit } from '@angular/core';
import { Router } from '@angular/router';

import { MarketplaceApiService, ProviderDetailResponse, SessionUser, TimelineEvent } from '../../../services/marketplace-api.service';

@Component({
  selector: 'app-profile',
  templateUrl: 'profile.page.html',
  styleUrls: ['profile.page.scss'],
  standalone: false,
})
export class ProfilePage implements OnInit {
  user: SessionUser | null = null;
  providerDetail: ProviderDetailResponse | null = null;
  bookingCount = 0;
  showSettings = false;
  showTimeline = false;
  timelineEvents: TimelineEvent[] = [];
  loadingTimeline = false;
  timelineLoaded = false;

  settingsForm = { fullName: '', email: '', notifications: true, defaultMunicipality: '' };
  settingsMessage = '';
  settingsSuccess = false;
  savingSettings = false;

  municipalities = ['Bongao', 'Simunul', 'Sitangkai', 'Panglima Sugala', 'Turtle Islands'];

  roleLabels: Record<string, string> = {
    client: 'Client',
    worker: 'Worker',
    agency: 'Agency',
    admin: 'Admin',
  };

  roleColors: Record<string, string> = {
    client: 'primary',
    worker: 'secondary',
    agency: 'tertiary',
    admin: 'danger',
  };

  roleIcons: Record<string, string> = {
    client: 'person-outline',
    worker: 'hammer-outline',
    agency: 'business-outline',
    admin: 'shield-checkmark-outline',
  };

  constructor(private readonly api: MarketplaceApiService, private readonly router: Router) {}

  get token(): string {
    return this.api.getToken();
  }

  get initials(): string {
    if (!this.user) return '?';
    const name = this.user.fullName || this.user.email;
    return name
      .split(' ')
      .map(n => n[0])
      .join('')
      .toUpperCase()
      .slice(0, 2);
  }

  get isProvider(): boolean {
    return this.user?.role === 'worker' || this.user?.role === 'agency';
  }

  get isApproved(): boolean {
    return this.user?.status === 'approved';
  }

  get reviewCount(): number {
    return this.providerDetail?.reviewSummary?.count ?? 0;
  }

  get averageRating(): number {
    return this.providerDetail?.reviewSummary?.average ?? 0;
  }

  ngOnInit(): void {
    this.user = this.api.getStoredUser();
    this.resetSettingsForm();
    this.loadStats();
  }

  loadStats(): void {
    if (!this.user) return;

    // Load bookings count
    this.api.getMyBookings(this.token).subscribe({
      next: (res) => {
        this.bookingCount = res.bookings.length;
      },
      error: () => {},
    });

    // Load provider review summary for workers/agencies
    if (this.isProvider) {
      this.api.getProviderDetail(this.user.id).subscribe({
        next: (res) => {
          this.providerDetail = res;
        },
        error: () => {},
      });
    }
  }

  toggleSettings(): void {
    this.showSettings = !this.showSettings;
    this.settingsMessage = '';
  }

  toggleTimeline(): void {
    this.showTimeline = !this.showTimeline;
    if (this.showTimeline && !this.timelineLoaded) {
      this.loadTimeline();
    }
  }

  loadTimeline(): void {
    this.loadingTimeline = true;

    this.api.getTimeline(this.token, 30).subscribe({
      next: (res) => {
        this.loadingTimeline = false;
        this.timelineLoaded = true;
        this.timelineEvents = res.events;
      },
      error: () => {
        this.loadingTimeline = false;
        this.timelineLoaded = true;
        this.timelineEvents = [];
      },
    });
  }

  timelineIcon(type: TimelineEvent['type']): string {
    const map: Record<string, string> = {
      booking: 'calendar-outline',
      review: 'star-outline',
      job_post: 'construct-outline',
      job_offer: 'mail-outline',
    };
    return map[type] || 'ellipse-outline';
  }

  timelineColor(type: TimelineEvent['type']): string {
    const map: Record<string, string> = {
      booking: 'primary',
      review: 'warning',
      job_post: 'success',
      job_offer: 'secondary',
    };
    return map[type] || 'medium';
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

  trackTimeline(_i: number, e: TimelineEvent): string {
    return `${e.type}-${e.id}`;
  }

  saveSettings(): void {
    if (!this.user) return;

    const fullName = this.settingsForm.fullName.trim();
    const email = this.settingsForm.email.trim();

    if (!fullName || !email) {
      this.settingsMessage = 'Name and email are required.';
      this.settingsSuccess = false;
      return;
    }

    this.savingSettings = true;

    this.user = { ...this.user, fullName, email };
    this.api.updateStoredUser(this.user);

    localStorage.setItem(
      'hanapgawa_profile_preferences',
      JSON.stringify({
        notifications: this.settingsForm.notifications,
        defaultMunicipality: this.settingsForm.defaultMunicipality.trim(),
      }),
    );

    setTimeout(() => {
      this.savingSettings = false;
      this.settingsSuccess = true;
      this.settingsMessage = 'Settings saved.';
    }, 400);
  }

  logout(): void {
    this.api.clearSession();
    this.router.navigate(['/onboarding'], { replaceUrl: true });
  }

  goToDashboard(): void {
    this.router.navigate(['/tabs/dashboard']);
  }

  private resetSettingsForm(): void {
    const rawPrefs = localStorage.getItem('hanapgawa_profile_preferences');
    let prefs: { notifications?: boolean; defaultMunicipality?: string } = {};
    try {
      prefs = rawPrefs ? (JSON.parse(rawPrefs) as { notifications?: boolean; defaultMunicipality?: string }) : {};
    } catch {
      prefs = {};
    }

    this.settingsForm = {
      fullName: this.user?.fullName || '',
      email: this.user?.email || '',
      notifications: prefs.notifications ?? true,
      defaultMunicipality: prefs.defaultMunicipality || '',
    };
  }
}
