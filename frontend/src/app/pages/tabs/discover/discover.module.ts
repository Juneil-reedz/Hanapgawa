import { CommonModule } from '@angular/common';
import { NgModule } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { IonicModule } from '@ionic/angular';

import { DiscoverPageRoutingModule } from './discover-routing.module';
import { DiscoverPage } from './discover.page';
import { ProviderDetailPage } from './provider-detail.page';

@NgModule({
  imports: [CommonModule, FormsModule, IonicModule, DiscoverPageRoutingModule],
  declarations: [DiscoverPage, ProviderDetailPage],
})
export class DiscoverPageModule {}
