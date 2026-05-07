import { NgModule } from '@angular/core';
import { RouterModule, Routes } from '@angular/router';

import { BookingsPage } from './bookings.page';
import { BookingDetailPage } from './booking-detail.page';

const routes: Routes = [
  { path: '', component: BookingsPage },
  { path: ':bookingId', component: BookingDetailPage },
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
})
export class BookingsPageRoutingModule {}
