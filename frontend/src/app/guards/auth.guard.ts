import { Injectable } from '@angular/core';
import { CanActivate, Router } from '@angular/router';

import { MarketplaceApiService } from '../services/marketplace-api.service';

@Injectable({ providedIn: 'root' })
export class AuthGuard implements CanActivate {
  constructor(private readonly api: MarketplaceApiService, private readonly router: Router) {}

  canActivate(): boolean {
    if (this.api.getToken()) {
      return true;
    }
    this.router.navigate(['/onboarding']);
    return false;
  }
}
