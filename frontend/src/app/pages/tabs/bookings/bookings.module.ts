import { CommonModule } from '@angular/common';
import { NgModule } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { IonicModule } from '@ionic/angular';

import { BookingsPageRoutingModule } from './bookings-routing.module';
import { BookingDetailPage } from './booking-detail.page';
import { BookingsPage } from './bookings.page';

@NgModule({
  imports: [CommonModule, FormsModule, IonicModule, BookingsPageRoutingModule],
  declarations: [BookingsPage, BookingDetailPage],
})
export class BookingsPageModule {}
