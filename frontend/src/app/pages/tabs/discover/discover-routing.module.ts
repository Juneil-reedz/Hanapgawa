import { NgModule } from '@angular/core';
import { RouterModule, Routes } from '@angular/router';

import { DiscoverPage } from './discover.page';
import { ProviderDetailPage } from './provider-detail.page';

const routes: Routes = [
  { path: '', component: DiscoverPage },
  { path: 'provider/:providerUserId', component: ProviderDetailPage },
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
})
export class DiscoverPageRoutingModule {}
