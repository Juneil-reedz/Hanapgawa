import { Component } from '@angular/core';
import { Router } from '@angular/router';

import { MarketplaceApiService } from '../../services/marketplace-api.service';

@Component({
  selector: 'app-onboarding',
  templateUrl: 'onboarding.page.html',
  styleUrls: ['onboarding.page.scss'],
  standalone: false,
})
export class OnboardingPage {
  features = [
    { icon: 'search-outline', title: 'Discover Providers', desc: 'Find approved workers and agencies across Tawi-Tawi.' },
    { icon: 'calendar-outline', title: 'Book Instantly', desc: 'Send booking requests directly from your phone.' },
    { icon: 'star-outline', title: 'Leave Reviews', desc: 'Rate completed jobs to help your community.' },
  ];

  constructor(private readonly router: Router, private readonly api: MarketplaceApiService) {
    if (this.api.getToken()) {
      this.router.navigate(['/tabs/discover'], { replaceUrl: true });
    }
  }

  goToAuth(): void {
    this.router.navigate(['/auth']);
  }
}
