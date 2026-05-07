import { Injectable, OnDestroy } from '@angular/core';
import { ToastController } from '@ionic/angular';

import { MarketplaceApiService } from './marketplace-api.service';
import { OfflineStorageService } from './offline-storage.service';

@Injectable({ providedIn: 'root' })
export class NetworkSyncService implements OnDestroy {
  private onlineHandler = () => this.onConnectionRestored();
  private offlineHandler = () => this.onConnectionLost();

  constructor(
    private readonly api: MarketplaceApiService,
    private readonly offline: OfflineStorageService,
    private readonly toast: ToastController,
  ) {}

  /** Call once from AppComponent to start listening. */
  start(): void {
    window.addEventListener('online', this.onlineHandler);
    window.addEventListener('offline', this.offlineHandler);

    // Sync on startup if already online and queue has items
    if (navigator.onLine) {
      this.syncIfNeeded();
    }
  }

  ngOnDestroy(): void {
    window.removeEventListener('online', this.onlineHandler);
    window.removeEventListener('offline', this.offlineHandler);
  }

  get isOnline(): boolean {
    return navigator.onLine;
  }

  private async onConnectionRestored(): Promise<void> {
    await this.showToast('Back online', 'checkmark-circle-outline', 'success', 1500);
    await this.syncIfNeeded();
  }

  private async onConnectionLost(): Promise<void> {
    await this.showToast('No internet — bookings will be saved offline', 'cloud-offline-outline', 'warning', 3000);
  }

  private async syncIfNeeded(): Promise<void> {
    const token = this.api.getToken();
    if (!token) return;

    const pending = await this.offline.getPendingCount();
    if (pending === 0) return;

    const result = await this.api.syncOfflineQueue(token);

    if (result.synced > 0) {
      await this.showToast(
        `${result.synced} offline booking${result.synced > 1 ? 's' : ''} synced`,
        'cloud-upload-outline',
        'success',
        3000,
      );
    }

    if (result.failed > 0) {
      await this.showToast(
        `${result.failed} booking${result.failed > 1 ? 's' : ''} failed to sync`,
        'alert-circle-outline',
        'warning',
        3000,
      );
    }
  }

  private async showToast(message: string, icon: string, color: string, duration: number): Promise<void> {
    const t = await this.toast.create({ message, icon, color, duration, position: 'top' });
    await t.present();
  }
}
