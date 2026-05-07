import { Component, OnInit } from '@angular/core';

import { MarketplaceApiService, SessionUser } from '../../services/marketplace-api.service';

@Component({
  selector: 'app-tabs',
  templateUrl: 'tabs.page.html',
  styleUrls: ['tabs.page.scss'],
  standalone: false,
})
export class TabsPage implements OnInit {
  user: SessionUser | null = null;

  get isProvider(): boolean {
    return this.user?.role === 'worker' || this.user?.role === 'agency' || this.user?.role === 'admin';
  }

  constructor(private readonly api: MarketplaceApiService) {}

  ngOnInit(): void {
    this.user = this.api.getStoredUser();
  }
}
