import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';

import { MarketplaceApiService, ProviderDetailResponse, ServiceListing } from '../../../services/marketplace-api.service';

@Component({
  selector: 'app-provider-detail',
  templateUrl: 'provider-detail.page.html',
  styleUrls: ['provider-detail.page.scss'],
  standalone: false,
})
export class ProviderDetailPage implements OnInit {
  detail: ProviderDetailResponse | null = null;
  loading = false;
  message = '';

  constructor(
    private readonly api: MarketplaceApiService,
    private readonly route: ActivatedRoute,
    private readonly router: Router,
  ) {}

  ngOnInit(): void {
    this.loadProvider();
  }

  loadProvider(): void {
    const providerUserId = this.route.snapshot.paramMap.get('providerUserId');
    if (!providerUserId) {
      this.message = 'Provider not found.';
      return;
    }

    this.loading = true;
    this.message = '';

    this.api.getProviderDetail(providerUserId).subscribe({
      next: (res) => {
        this.loading = false;
        this.detail = res;
      },
      error: (err: HttpErrorResponse) => {
        this.loading = false;
        this.message = err.error?.error?.message || 'Could not load provider profile.';
      },
    });
  }

  openListing(listing: ServiceListing): void {
    this.router.navigate(['/tabs/discover'], { queryParams: { keyword: listing.title } });
  }

  trackListing(_i: number, listing: ServiceListing): string {
    return listing.id;
  }

  trackReview(_i: number, review: { id: string }): string {
    return review.id;
  }
}
