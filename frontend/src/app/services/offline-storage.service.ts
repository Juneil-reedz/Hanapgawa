import { Injectable } from '@angular/core';
import { Storage } from '@ionic/storage-angular';

import { BookingPayload, ProviderProfile } from './marketplace-api.service';

export interface QueuedBooking {
  id: string;
  payload: BookingPayload;
  queuedAt: string;
}

const KEYS = {
  providerCache: 'hg_provider_cache',
  providerCacheTime: 'hg_provider_cache_time',
  bookingQueue: 'hg_booking_queue',
};

const CACHE_TTL_MS = 30 * 60 * 1000; // 30 minutes

@Injectable({ providedIn: 'root' })
export class OfflineStorageService {
  private ready: Promise<void>;

  constructor(private readonly storage: Storage) {
    this.ready = this.storage.create().then(() => undefined);
  }

  /* ── Provider cache ────────────────────────────────────────────────── */

  async cacheProviders(profiles: ProviderProfile[]): Promise<void> {
    await this.ready;
    await this.storage.set(KEYS.providerCache, profiles);
    await this.storage.set(KEYS.providerCacheTime, Date.now());
  }

  async getCachedProviders(): Promise<ProviderProfile[] | null> {
    await this.ready;
    const cachedAt = await this.storage.get(KEYS.providerCacheTime);

    if (!cachedAt || Date.now() - cachedAt > CACHE_TTL_MS) {
      return null;
    }

    return this.storage.get(KEYS.providerCache);
  }

  async clearProviderCache(): Promise<void> {
    await this.ready;
    await this.storage.remove(KEYS.providerCache);
    await this.storage.remove(KEYS.providerCacheTime);
  }

  /* ── Booking offline queue ─────────────────────────────────────────── */

  async queueBooking(payload: BookingPayload): Promise<QueuedBooking> {
    await this.ready;
    const queue = await this.getPendingQueue();
    const entry: QueuedBooking = {
      id: crypto.randomUUID(),
      payload,
      queuedAt: new Date().toISOString(),
    };
    queue.push(entry);
    await this.storage.set(KEYS.bookingQueue, queue);
    return entry;
  }

  async getPendingQueue(): Promise<QueuedBooking[]> {
    await this.ready;
    return (await this.storage.get(KEYS.bookingQueue)) || [];
  }

  async removePendingBooking(id: string): Promise<void> {
    await this.ready;
    const queue = await this.getPendingQueue();
    await this.storage.set(KEYS.bookingQueue, queue.filter(q => q.id !== id));
  }

  async clearQueue(): Promise<void> {
    await this.ready;
    await this.storage.set(KEYS.bookingQueue, []);
  }

  async getPendingCount(): Promise<number> {
    const queue = await this.getPendingQueue();
    return queue.length;
  }
}
